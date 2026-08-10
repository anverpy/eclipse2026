"""DGT camera poller — brillo medio por frame via nap.dgt.es camera snapshots.

Camera device catalog + per-camera live JPEG URL (fse:deviceUrl) come from the
public "Cámaras DGT DATEX2 v3.7" NAP-DGT feed, no API key needed (verified
2026-08-09). Rather than re-parsing the ~3.7MB device catalog on every
invocation, a curated set of one camera per totality-path province is
hardcoded below (picked by reading that catalog once — see CHANGELOG).

fetch() downloads each camera's current JPEG and computes mean brightness with
PIL (imported lazily so this module stays importable — and mockable offline —
without Pillow installed; the real runtime dependency ships as a Lambda layer,
see terraform/lambda_dgt_camera.tf).
"""

import io
import os
import time
import urllib.request
from datetime import datetime, timezone

from lambdas.common.envelope import make_envelope
from lambdas.common.s3_writer import write_records

METRIC_NAME = "brillo_medio"
UNIT = "0_255"

# During totality (event.tier == "tight") a single 1-minute EventBridge tick
# fans out into a few internal captures instead of one — EventBridge
# Scheduler's rate() floors at 1 minute, so sub-minute cadence can only come
# from looping inside an invocation. Bounded by the Lambda's own timeout
# (see terraform/lambda_dgt_camera.tf) as an independent stop.
TIGHT_TICKS = 3
TIGHT_TICK_INTERVAL_S = 20

# camera_id -> (province, road, lat, lon); deviceUrl is always
# https://etraffic.dgt.es/camarasEtraffic/<camera_id>.jpg
CAMERAS = {
    "167942": ("LUGO", "N-6", 42.968063, -7.500288),
    "168070": ("ASTURIAS", "AP-66", 43.11356, -5.819016),
    "176134": ("LEÓN", "A-6", 42.2278, -5.8148),
    "176130": ("BURGOS", "A-62", 42.2624, -3.9403),
    "638": ("SORIA", "A-2", 41.129097, -2.4469147),
    "48": ("ZARAGOZA", "A-2", 41.39441, -1.5488539),
    "165066": ("TERUEL", "N-232", 41.06493, -0.2116359),
    "95": ("CASTELLÓN", "A-23", 39.780052, -0.39301112),
    "164075": ("A CORUÑA", "AC-14", 43.307865, -8.403962),
}

IMAGE_URL = "https://etraffic.dgt.es/camarasEtraffic/{camera_id}.jpg"


def fetch(event: dict) -> list:
    from PIL import Image, ImageStat  # lazy: only needed for the real call, not local/mock mode

    frames = []
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for camera_id, (province, road, lat, lon) in CAMERAS.items():
        url = IMAGE_URL.format(camera_id=camera_id)
        try:
            with urllib.request.urlopen(url, timeout=10) as resp:
                img_bytes = resp.read()
            img = Image.open(io.BytesIO(img_bytes)).convert("L")
            brightness = ImageStat.Stat(img).mean[0]
        except Exception as exc:  # best-effort per camera — one broken feed shouldn't drop the rest
            print(f"dgt_camera: skipping {camera_id} ({province}): {exc}")
            continue
        frames.append(
            {
                "camera_id": camera_id,
                "province": province,
                "road": road,
                "lat": lat,
                "lon": lon,
                "captured_at": now,
                "brightness": round(brightness, 1),
            }
        )
    return frames


def _capture_tick(event: dict, bucket: str | None) -> list:
    raw = fetch(event)
    records = [
        make_envelope(
            source="dgt_camera",
            ts_utc=frame["captured_at"],
            station_or_camera_id=frame["camera_id"],
            lat=frame.get("lat"),
            lon=frame.get("lon"),
            metric_name=METRIC_NAME,
            value=frame["brightness"],
            unit=UNIT,
            raw=frame,
        )
        for frame in raw
    ]
    if records and bucket:
        write_records(bucket, "dgt_camera", records)
    return records


def handler(event: dict, context=None) -> dict:
    bucket = os.environ.get("DATA_LAKE_BUCKET")
    ticks = TIGHT_TICKS if event.get("tier") == "tight" else 1

    all_records = []
    for i in range(ticks):
        all_records.extend(_capture_tick(event, bucket))
        if i < ticks - 1:
            time.sleep(TIGHT_TICK_INTERVAL_S)

    return {"source": "dgt_camera", "count": len(all_records), "records": all_records}
