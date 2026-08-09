"""AEMET poller — temperatura via opendata.aemet.es (observación convencional, todas las estaciones).

Two-step API: first call (with api_key header) returns a short-lived URL to the
actual data; fetch() resolves both steps and returns the final list of station
observations already filtered to the eclipse totality-path stations. Response
body is Latin-1 encoded (AEMET quirk, not UTF-8).
"""

import json
import os
import urllib.request
from datetime import datetime, timezone

from lambdas.common.envelope import make_envelope
from lambdas.common.s3_writer import write_records

METRIC_NAME = "temperatura"
UNIT = "C"

STEP1_URL = "https://opendata.aemet.es/opendata/api/observacion/convencional/todas"

# one representative station per city along the totality path (README route:
# A Coruña -> Palma), picked from the full ~10k station dump by matching "ubi".
STATIONS = {
    "1387": "A Coruña",
    "1505": "Lugo",
    "1249X": "Oviedo",
    "2661": "León",
    "2331": "Burgos",
    "2030": "Soria",
    "9434": "Zaragoza",
    "8368U": "Teruel",
    "8500A": "Castellón",
    "B278": "Palma de Mallorca",
}


def fetch(event: dict) -> list:
    key = os.environ["AEMET_API_KEY"]
    try:
        req1 = urllib.request.Request(STEP1_URL, headers={"api_key": key})
        with urllib.request.urlopen(req1, timeout=15) as resp:
            meta = json.loads(resp.read().decode("utf-8"))

        with urllib.request.urlopen(meta["datos"], timeout=20) as resp:
            data = json.loads(resp.read().decode("latin-1"))
    except Exception as exc:
        # live-day resilience: a transient AEMET blip should skip this cycle,
        # not fail the invocation — next scheduled poll just tries again.
        print(f"aemet: fetch failed, skipping this cycle: {exc}")
        return []

    return [obs for obs in data if obs.get("idema") in STATIONS]


def handler(event: dict, context=None) -> dict:
    raw = fetch(event)
    records = []
    for obs in raw:
        if "ta" not in obs:
            continue
        ts_utc = (
            datetime.fromisoformat(obs["fint"]).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        )
        records.append(
            make_envelope(
                source="aemet",
                ts_utc=ts_utc,
                station_or_camera_id=obs["idema"],
                lat=obs.get("lat"),
                lon=obs.get("lon"),
                metric_name=METRIC_NAME,
                value=obs["ta"],
                unit=UNIT,
                raw=obs,
            )
        )
    bucket = os.environ.get("DATA_LAKE_BUCKET")
    if records and bucket:
        write_records(bucket, "aemet", records)
    return {"source": "aemet", "count": len(records), "records": records}
