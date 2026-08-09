"""DGT traffic poller — incidencias activas via nap.dgt.es (DATEX2 v3.7 SituationPublication).

Public pull URL, no API key / registration needed (verified 2026-08-09). Note this
covers *incidents* (roadworks, accidents, congestion...), not raw vehicle-count
"intensidad" — NAP-DGT has no live traffic-intensity/aforo dataset, only the
historic IMD one, so the metric here is incident presence, not vehicle throughput
(see README source #3 for the original, broader ambition).

Real fetch() pulls the DATEX2 XML and parses it into the list-of-dicts shape
below (the XML->JSON step lives inside fetch(), per README architecture),
filtered to the eclipse totality-path provinces to keep volume down.
"""

import os
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

from lambdas.common.envelope import make_envelope
from lambdas.common.s3_writer import write_records

METRIC_NAME = "incidencia_activa"
UNIT = "count"

FEED_URL = "https://nap.dgt.es/datex2/v3/dgt/SituationPublication/datex2_v37.xml"

# provinces the totality path passes through (README: A Coruña -> Palma).
TOTALITY_PROVINCES = {
    "LUGO", "ASTURIAS", "LEON", "LEÓN", "BURGOS", "SORIA", "ZARAGOZA",
    "TERUEL", "CASTELLON", "CASTELLÓN", "CASTELLÓN/CASTELLÓ",
    "CORUÑA, A", "A CORUÑA", "BALEARES", "ILLES BALEARS",
}


def _local(tag: str) -> str:
    return tag.split("}", 1)[-1] if "}" in tag else tag


def _find_text(elem, name):
    for e in elem.iter():
        if _local(e.tag) == name and e.text:
            return e.text.strip()
    return None


def fetch(event: dict) -> list:
    try:
        with urllib.request.urlopen(FEED_URL, timeout=15) as resp:
            root = ET.fromstring(resp.read())
    except Exception as exc:
        # live-day resilience: a transient NAP-DGT blip should skip this cycle,
        # not fail the invocation — next scheduled poll just tries again.
        print(f"dgt_traffic: fetch failed, skipping this cycle: {exc}")
        return []

    points = []
    for situation in root.iter():
        if _local(situation.tag) != "situation":
            continue
        province = (_find_text(situation, "province") or "").upper()
        if province not in TOTALITY_PROVINCES:
            continue
        if _find_text(situation, "validityStatus") != "active":
            continue

        lat = _find_text(situation, "latitude")
        lon = _find_text(situation, "longitude")
        start_time = _find_text(situation, "overallStartTime")
        points.append(
            {
                "id": situation.get("id"),
                "province": province,
                "cause": _find_text(situation, "causeType"),
                "ts": start_time,
                "lat": float(lat) if lat else None,
                "lon": float(lon) if lon else None,
            }
        )
    return points


def handler(event: dict, context=None) -> dict:
    raw = fetch(event)
    records = []
    for point in raw:
        ts = point["ts"]
        ts_utc = (
            datetime.fromisoformat(ts).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            if ts
            else None
        )
        if not ts_utc:
            continue
        records.append(
            make_envelope(
                source="dgt_traffic",
                ts_utc=ts_utc,
                station_or_camera_id=point["id"],
                lat=point.get("lat"),
                lon=point.get("lon"),
                metric_name=METRIC_NAME,
                value=1,
                unit=UNIT,
                raw=point,
            )
        )
    bucket = os.environ.get("DATA_LAKE_BUCKET")
    if records and bucket:
        write_records(bucket, "dgt_traffic", records)
    return {"source": "dgt_traffic", "count": len(records), "records": records}
