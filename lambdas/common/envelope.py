"""Unified envelope schema shared by all eclipse2026 source Lambdas (see README)."""

REQUIRED_FIELDS = {
    "source": str,
    "ts_utc": str,
    "station_or_camera_id": str,
    "lat": (float, int, type(None)),
    "lon": (float, int, type(None)),
    "metric_name": str,
    "value": (float, int),
    "unit": str,
    "raw": dict,
}


def validate_envelope(record: dict) -> None:
    for field, expected_type in REQUIRED_FIELDS.items():
        if field not in record:
            raise ValueError(f"envelope missing required field '{field}': {record}")
        if not isinstance(record[field], expected_type):
            raise TypeError(
                f"envelope field '{field}' expected {expected_type}, "
                f"got {type(record[field])}: {record}"
            )


def make_envelope(
    *, source, ts_utc, station_or_camera_id, lat, lon, metric_name, value, unit, raw
) -> dict:
    record = {
        "source": source,
        "ts_utc": ts_utc,
        "station_or_camera_id": station_or_camera_id,
        "lat": lat,
        "lon": lon,
        "metric_name": metric_name,
        "value": value,
        "unit": unit,
        "raw": raw,
    }
    validate_envelope(record)
    return record
