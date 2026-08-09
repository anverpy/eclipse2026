"""Google Trends poller — interes de busqueda via the unofficial trends.google.com API
(no pytrends dependency: same 3-call flow it wraps, done here with stdlib urllib so
this source doesn't need its own Lambda layer).

Flow: (1) GET trends.google.com/?geo=ES to pick up the anti-bot "NID" cookie,
(2) GET .../api/explore with the search request to get a per-widget token,
(3) GET .../api/widgetdata/multiline with that token for the actual timeseries.
Every response is prefixed with ")]}'," which must be stripped before JSON parsing.

Low priority per README: unofficial/scraped, real risk of 429/block (confirmed
live from this dev box without a browser User-Agent — a bare urllib request
gets blocked immediately). fetch() therefore catches everything and returns an
empty list on any failure rather than raising, so one blocked cycle never
takes down the rest of the pipeline.
"""

import http.cookiejar
import json
import os
import urllib.parse
import urllib.request
from datetime import datetime, timezone

from lambdas.common.envelope import make_envelope
from lambdas.common.s3_writer import write_records

METRIC_NAME = "interes_busqueda"
UNIT = "index_0_100"
STATION_ID = "google_trends_es"

KEYWORD = "eclipse"
GEO = "ES"
# a real browser UA is required — trends.google.com blocks the default urllib UA outright.
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"


def _get(opener, url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with opener.open(req, timeout=10) as resp:
        return resp.read().decode("utf-8")


def fetch(event: dict) -> list:
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    try:
        _get(opener, f"https://trends.google.com/?geo={GEO}")

        explore_req = urllib.parse.quote(
            json.dumps(
                {"comparisonItem": [{"keyword": KEYWORD, "geo": GEO, "time": "now 1-d"}], "category": 0, "property": ""},
                separators=(",", ":"),
            )
        )
        widgets = json.loads(_get(opener, f"https://trends.google.com/trends/api/explore?hl=en-US&tz=-120&req={explore_req}")[5:])["widgets"]
        timeseries = next(w for w in widgets if w["id"] == "TIMESERIES")

        widget_req = urllib.parse.quote(json.dumps(timeseries["request"], separators=(",", ":")))
        multiline_url = (
            f"https://trends.google.com/trends/api/widgetdata/multiline"
            f"?hl=en-US&tz=-120&req={widget_req}&token={timeseries['token']}"
        )
        timeline = json.loads(_get(opener, multiline_url)[5:])["default"]["timelineData"]
    except Exception as exc:
        print(f"trends: fetch failed, skipping this cycle (best-effort source): {exc}")
        return []

    return [
        {"time_unix": point["time"], "value": point["value"][0]}
        for point in timeline
        if point.get("hasData", [True])[0]
    ]


def handler(event: dict, context=None) -> dict:
    raw = fetch(event)
    records = [
        make_envelope(
            source="trends",
            ts_utc=datetime.fromtimestamp(int(point["time_unix"]), tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            station_or_camera_id=STATION_ID,
            lat=None,
            lon=None,
            metric_name=METRIC_NAME,
            value=point["value"],
            unit=UNIT,
            raw=point,
        )
        for point in raw
    ]
    bucket = os.environ.get("DATA_LAKE_BUCKET")
    if records and bucket:
        write_records(bucket, "trends", records)
    return {"source": "trends", "count": len(records), "records": records}
