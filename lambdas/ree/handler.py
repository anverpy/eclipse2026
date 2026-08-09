"""REE poller — generacion fotovoltaica medida via api.esios.ree.es.

fetch() is the real API call, kept separate from handler() so scripts/local_dev.py
can monkeypatch this exact attribute in mock mode. Token read from ESIOS_TOKEN env
var at runtime (set by terraform from terraform.tfvars, see README) — never logged.
"""

import json
import os
import urllib.request
from datetime import datetime, timedelta, timezone

from lambdas.common.envelope import make_envelope
from lambdas.common.s3_writer import write_records

METRIC_NAME = "generacion_fotovoltaica"
UNIT = "MW"

# indicator 1295 = "Generación T.Real Solar fotovoltaica" (geo_id 8741 = Peninsula),
# ~5min resolution — picked over 1161 ("Generación medida", geo_id 8741 too but
# returns 0 values, looks discontinued) by listing GET /indicators and sampling.
INDICATOR_ID = 1295
LOOKBACK_MINUTES = 15

# geo_id -> approximate lat/lon for the totality-path region (indicator reports
# per-geo_id, not per-station; refine if a finer-grained indicator is found).
GEO_COORDS = {
    8741: (40.4, -3.7),  # Peninsula (placeholder, no single point really applies)
}


def fetch(event: dict) -> dict:
    token = os.environ["ESIOS_TOKEN"]
    end = datetime.now(timezone.utc)
    start = end - timedelta(minutes=LOOKBACK_MINUTES)
    url = (
        f"https://api.esios.ree.es/indicators/{INDICATOR_ID}"
        f"?start_date={start:%Y-%m-%dT%H:%M:%S}&end_date={end:%Y-%m-%dT%H:%M:%S}"
    )
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json; application/vnd.esios-api-v1+json",
            "Content-Type": "application/json",
            "x-api-key": token,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as exc:
        # live-day resilience: a transient ESIOS blip should skip this cycle,
        # not fail the invocation — next scheduled poll just tries again.
        print(f"ree: fetch failed, skipping this cycle: {exc}")
        return {"indicator": {"values": []}}


def handler(event: dict, context=None) -> dict:
    raw = fetch(event)
    records = []
    for v in raw["indicator"]["values"]:
        geo_id = v["geo_id"]
        lat, lon = GEO_COORDS.get(geo_id, (None, None))
        records.append(
            make_envelope(
                source="ree",
                ts_utc=v["datetime_utc"],
                station_or_camera_id=str(geo_id),
                lat=lat,
                lon=lon,
                metric_name=METRIC_NAME,
                value=v["value"],
                unit=UNIT,
                raw=v,
            )
        )
    bucket = os.environ.get("DATA_LAKE_BUCKET")
    if records and bucket:
        write_records(bucket, "ree", records)
    return {"source": "ree", "count": len(records), "records": records}
