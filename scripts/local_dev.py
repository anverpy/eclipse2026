#!/usr/bin/env python3
"""Local dev/test harness for eclipse2026 source Lambdas — no network, no AWS.

Runs each source's handler(event, context) with its fetch() monkeypatched to
return the fixture in lambdas/<source>/fixtures/sample_response.json, then
validates every emitted record against the unified envelope schema. Lets you
iterate on the fetch->envelope mapping for a source without touching AWS or
the real API. This is the "modo local" flagged as pending in README.md.

Usage:
  scripts/local_dev.py list
  scripts/local_dev.py run <source> [--event path.json]
  scripts/local_dev.py run-all
"""

import argparse
import importlib
import json
import sys
from pathlib import Path
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from lambdas.common.envelope import validate_envelope  # noqa: E402

# mirrors the SOURCES registry in admin.sh — keep both in sync when adding a source.
SOURCES = ["ree", "aemet", "dgt_traffic", "trends", "dgt_camera"]

DEFAULT_EVENT = {"source": "local_dev", "mode": "test"}


def run_source(name: str, event: dict) -> dict:
    module = importlib.import_module(f"lambdas.{name}.handler")
    fixture_path = REPO_ROOT / "lambdas" / name / "fixtures" / "sample_response.json"
    fixture = json.loads(fixture_path.read_text())

    with patch.object(module, "fetch", return_value=fixture):
        result = module.handler(event, None)

    for record in result["records"]:
        validate_envelope(record)

    return result


def cmd_list(_args):
    for name in SOURCES:
        print(name)


def cmd_run(args):
    event = json.loads(Path(args.event).read_text()) if args.event else DEFAULT_EVENT
    result = run_source(args.source, event)
    print(json.dumps(result, indent=2, ensure_ascii=False))


def cmd_run_all(_args):
    failed = []
    for name in SOURCES:
        print(f"--- {name} ---")
        try:
            result = run_source(name, DEFAULT_EVENT)
            print(f"OK — {result['count']} record(s)")
        except NotImplementedError as e:
            print(f"SKIP — {e}")
            failed.append(name)
        except Exception as e:
            print(f"FAIL — {type(e).__name__}: {e}")
            failed.append(name)
    print()
    if not failed:
        print(f"all {len(SOURCES)} sources OK")
    else:
        print(f"NOT OK: {', '.join(failed)}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="list known sources").set_defaults(func=cmd_list)

    p_run = sub.add_parser("run", help="run one source's handler against its fixture")
    p_run.add_argument("source", choices=SOURCES)
    p_run.add_argument("--event", help="path to a custom event JSON file")
    p_run.set_defaults(func=cmd_run)

    sub.add_parser("run-all", help="run every source, print pass/fail summary").set_defaults(func=cmd_run_all)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
