"""Shared S3 writer for eclipse2026 source Lambdas — ndjson, partitioned by source/date/hour."""

import json
import uuid
from datetime import datetime, timezone

import boto3

_s3 = boto3.client("s3")


def write_records(bucket: str, source: str, records: list) -> str:
    now = datetime.now(timezone.utc)
    key = (
        f"source={source}/dt={now:%Y-%m-%d}/hour={now:%H}/"
        f"{now:%Y%m%dT%H%M%S}-{uuid.uuid4().hex[:8]}.json"
    )
    body = "\n".join(json.dumps(r, ensure_ascii=False) for r in records)
    _s3.put_object(Bucket=bucket, Key=key, Body=body.encode("utf-8"), ContentType="application/x-ndjson")
    return key
