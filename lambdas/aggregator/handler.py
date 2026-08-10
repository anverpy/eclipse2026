"""Aggregator — republishes today's ingested data as one public JSON snapshot
for the live dashboard (docs/).

Reads S3 directly (not Athena): deterministic runtime and no per-query cost
or latency, which matters more here since this runs on a tight refresh
cadence rather than an ad-hoc query. `raw` is dropped from the public
payload to keep it small — full per-source detail stays queryable via
Athena (see terraform/glue.tf) for anyone who wants to dig in.
"""

import json
import os
import time
from datetime import datetime, timezone

import boto3

_s3 = boto3.client("s3")

SOURCES = ["ree", "aemet", "dgt_traffic", "trends", "dgt_camera"]

# Mirrors dgt_camera's tight-tier tick loop (see lambdas/dgt_camera/handler.py)
# so the public snapshot actually refreshes as often as the camera captures
# during totality, instead of sitting on stale data for a full 1-minute tick.
TIGHT_TICKS = 3
TIGHT_TICK_INTERVAL_S = 20

# human-readable label per record, pulled from `raw` (which the public
# payload otherwise drops entirely) — small-multiples charts need it since
# station_or_camera_id alone is an opaque code (AEMET idema, NAP-DGT camera
# id, ...).
_LABEL_FROM_RAW = {
    "ree": lambda raw: raw.get("geo_name"),
    "aemet": lambda raw: raw.get("ubi"),
    "dgt_traffic": lambda raw: raw.get("province"),
    "dgt_camera": lambda raw: raw.get("province"),
    "trends": lambda raw: "Google Trends (ES)",
}


def _read_source(bucket: str, source: str, dt: str) -> list:
    records = []
    label_fn = _LABEL_FROM_RAW[source]
    prefix = f"source={source}/dt={dt}/"
    paginator = _s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            body = _s3.get_object(Bucket=bucket, Key=obj["Key"])["Body"].read().decode("utf-8")
            for line in body.splitlines():
                if not line.strip():
                    continue
                r = json.loads(line)
                records.append(
                    {
                        "ts_utc": r["ts_utc"],
                        "station_or_camera_id": r["station_or_camera_id"],
                        "label": label_fn(r.get("raw", {})) or r["station_or_camera_id"],
                        "lat": r["lat"],
                        "lon": r["lon"],
                        "metric_name": r["metric_name"],
                        "value": r["value"],
                        "unit": r["unit"],
                    }
                )
    records.sort(key=lambda r: r["ts_utc"])
    return records


def _publish_snapshot(data_bucket: str, public_bucket: str) -> dict:
    dt = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    snapshot = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "dt": dt,
        "sources": {source: _read_source(data_bucket, source, dt) for source in SOURCES},
    }

    body = json.dumps(snapshot, ensure_ascii=False)
    _s3.put_object(
        Bucket=public_bucket,
        Key="latest.json",
        Body=body.encode("utf-8"),
        ContentType="application/json",
        CacheControl="public, max-age=15",
    )
    return {"bytes": len(body), "counts": {k: len(v) for k, v in snapshot["sources"].items()}}


def handler(event: dict, context=None) -> dict:
    data_bucket = os.environ["DATA_LAKE_BUCKET"]
    public_bucket = os.environ["PUBLIC_BUCKET"]
    ticks = TIGHT_TICKS if event.get("tier") == "tight" else 1

    result = None
    for i in range(ticks):
        result = _publish_snapshot(data_bucket, public_bucket)
        if i < ticks - 1:
            time.sleep(TIGHT_TICK_INTERVAL_S)
    return result
