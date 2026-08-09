# Technical plan: multi-source ingestion — Solar eclipse, August 12, 2026

## Event context

- Total solar eclipse, **August 12, 2026**, Spain.
- Totality path: A Coruña → Palma, passing through Lugo, Asturias, León, Burgos, Soria, Zaragoza, Teruel, Castellón.
- Totality: ~20:27–20:35h (duration 1–1.7 min). Partial phase from ~19:30h.
- Target ingestion window: **18:30–21:30h**.
- Document drafted: August 7, 2026, last updated August 9 → **3 days left** until the event.

## Project goal

(Semi-)automatic multi-source ingestion pipeline on AWS, as a data engineering portfolio project, that "goes wild" on eclipse day. Explicit priority: **minimum AWS cost** (or alternative hosting) over architectural sophistication or visualization.

## Cost goal (cross-cutting constraint)

- Minimize cost as a design criterion, not a later optimization.
- Maximize free-tier use: Lambda, S3, minimal Glue, Athena on-demand.
- Single-day event, low-medium volume → preliminary estimate: a few dollars, worst-case cap ~$10-20 USD.
- **Mandatory action**: AWS Budgets alarm from project kickoff (real risk of leaving resources running given the tight timeline).
- Always prefer pay-per-use serverless services over resources with a fixed hourly cost.

## Data sources (5) and current status

**All 5 sources are deployed and tested live against real AWS** (Lambda → S3 direct, no Kinesis/Firehose/DynamoDB — see decision 8). Details on how each one got built are in CHANGELOG.md (2026-08-09); here's just the final state.

### 1. REE — electricity generation (photovoltaic)
- ESIOS indicator `1295` ("Generación T.Real Solar fotovoltaica", geo_id 8741 Peninsula, ~5min resolution). Token in `terraform/terraform.tfvars` (gitignored, never in this README).
- Relevant usage condition for the architecture: if the project goes public, data must be served from your own server (no direct calls to REE) and avoid mass/redundant requests.
- "Hero" real-time source of the project.

### 2. AEMET — weather (temperature)
- API: AEMET OpenData (`opendata.aemet.es`), two-step flow, key in `terraform.tfvars`.
- 10 curated stations along the totality path (one per city).

### 3. DGT — traffic (active incidents)
- API: NAP-DGT (`nap.dgt.es`), DATEX2 feed **public, no registration or key needed** (1min refresh).
- Metric: `incidencia_activa` (DATEX2 incident presence — NAP-DGT has no public real-time traffic-volume/count feed, so this source covers incidents, not vehicle intensity), filtered to totality-path provinces.

### 4. Google Trends — search interest
- No official API, no `pytrends`: the same 3-call flow `pytrends` wraps, done by hand with `urllib` (cookie + explore + multiline) to avoid an extra dependency/layer.
- Low priority, best-effort — `fetch()` never lets a Google block take down the Lambda, degrades to 0 records.

### 5. Official traffic cameras (NAP-DGT)
- Same public source as source 3. 9 curated cameras, one per totality-path province (Lugo, Asturias, León, Burgos, Soria, Zaragoza, Teruel, Castellón, A Coruña).
- **Closed decision**: use official NAP-DGT cameras, not loose tourist webcams (lower legal/stability risk; the movement data is a secondary aggregate of the report, not the centerpiece).
- Metric: mean brightness per frame (Pillow, packaged as a Lambda layer — no Docker, manylinux wheel via `pip --platform`).
- Cadence: 2min in the 18:30–21:30h window; 1min in 20:15–20:45h (EventBridge Scheduler's `rate()` floor — the original 10-15s target would need a Lambda with an internal loop or Step Functions, evaluate after the dry run).

## Out of scope (dropped for live ingestion)

- **Hospital ER admissions by reason**: no public real-time source exists in Spain (protected health data).
- Partial alternative: Castilla y León open-data portal (within the totality path) publishes ER data with triage level, hospital, province, age, sex — but with **monthly** updates.
- Treatment: possible retrospective analysis (phase 2, weeks after the event), **out of the live 12-A pipeline**.

## Unified data schema

Common envelope for all sources, meant to allow unifying everything into a single partitioned Athena table:

```json
{
  "source": "ree | aemet | dgt_traffic | trends | dgt_camera",
  "ts_utc": "ISO8601",
  "station_or_camera_id": "string",
  "lat": "float",
  "lon": "float",
  "metric_name": "string",
  "value": "float",
  "unit": "string",
  "raw": {}
}
```

Partition in S3: `source=<X>/dt=2026-08-12/hour=<HH>/`

## AWS architecture

- **Orchestration**: EventBridge Scheduler, 16 schedules bounded by `start_date`/`end_date` to 2026-08-11 (dry run) and 2026-08-12 (event) only — inert outside those windows. Two cadence tiers (normal + tighter during the totality sub-window 20:15–20:45) for `ree`/`dgt_traffic`/`dgt_camera`; flat cadence for `aemet` (10min) and `trends` (20min).
- **Ingestion**: all 5 sources are Lambda → S3 direct (no Kinesis/Firehose/DynamoDB — decision 8, simplicity and cost over real-time "hero" streaming). XML→JSON (DGT) and all other parsing live inside each `fetch()`.
- **Storage**: S3 (`eclipse2026-data-lake`) as data lake / landing zone, partitioned `source=<X>/dt=<date>/hour=<HH>/`, ndjson.
- **Catalog**: Glue Data Catalog, database `eclipse2026_db`, single table `events` — **done** (`terraform/glue.tf`). No Crawler: schema is fixed (matches the unified envelope) and partitions (`source`/`dt`/`hour`) use **partition projection** instead of crawler/MSCK REPAIR — zero standing infra, no drift vs. actual S3 keys. `raw` is typed `string` (OpenX JsonSerDe auto-serializes the nested per-source JSON into it); query it with `json_extract()`.
- **Query**: Athena — **done** (`terraform/athena.tf`). Workgroup `eclipse2026-wg`, dedicated results bucket, 1 GiB/query scanned cap (cost guardrail). Verified live against real `dt=2026-08-09` data (`ree`, `dgt_camera`).
- **Visualization**: scope TBD (QuickSight vs. homemade dashboard) — **pending**.

## Key decisions already made

1. Cameras: official NAP-DGT ones, not loose webcams. **Closed.**
2. ER admissions by reason: out of the live pipeline, possible retrospective phase 2. **Closed.**
3. REE: use ESIOS (indicator `1295`, token received) instead of REData — better temporal resolution (~5min) and the same response shape the code already expected. **Closed** (see also decision 8).
4. General priority: robustness of ingestion across the 5 sources during the event over dashboard sophistication. **Closed.**
5. Minimum cost as a design constraint in every architecture decision. **Closed.**
6. IaC: **Terraform** (not CDK/SAM) — full coverage of every needed service in one tool, and `terraform destroy` gives guaranteed one-command teardown (critical given the cost risk in point 5). **Closed.**
7. IAM: **one Lambda execution role per source** (not a shared role) — same cost (IAM is free), better least-privilege. Each role only has access to its own S3 prefix (`source=<X>/*`) and its own log group. Defined in `terraform/iam.tf`. **Closed.**
8. Final ingestion pattern for all 5 sources: **Lambda → S3 direct**, no Kinesis/Firehose/DynamoDB — simplicity and cost over real-time "hero" streaming. IAM roles keep unused Kinesis/DynamoDB permissions (harmless, no cost). **Closed.**
9. DGT traffic: metric redefined from "intensity" to `incidencia_activa` — NAP-DGT has no public real-time traffic-volume feed, only DATEX2 incidents. **Closed.**
10. Catalog/query layer: hand-written Glue table (not Crawler-inferred) + partition projection (not MSCK REPAIR/Crawler-driven partition discovery) — schema is already known (envelope.py), so a Crawler would only add cost/moving parts without adding information. `raw` typed as `string`, not `struct`, since its shape varies per source. **Closed.**

## Still to decide

- **Minimal dashboard** (QuickSight vs. homemade) — immediate next step (Aug 10). Glue Catalog + Athena done (Aug 9, see "AWS architecture").
- Sub-minute (10-15s) camera cadence during totality — currently 1min due to EventBridge Scheduler's `rate()` floor; would need a Lambda with an internal loop or Step Functions. Evaluate after the dry run if 1min turns out insufficient.
- Live dashboard scope (QuickSight vs. homemade) — depends on how much time is left after Glue/Athena.
- Rotate `andrew`'s access key (active unrotated since 2026-03-09) before closing out the project.

## Calendar (from August 7)

- **Aug 7**: AEMET signup, initial technical plan, AWS account, Terraform installed. ✅
- **Aug 8**: ESIOS token received, local dev mode (fixtures + harness). ✅
- **Aug 9 (today)**: all 5 sources with real `fetch()`, deployed and tested live against AWS (not just `local`); EventBridge Scheduler configured and bounded to dry run + event; Glue Data Catalog + Athena table deployed and verified against live data. Ahead of today's plan. ✅
- **Aug 10**: minimal dashboard. **Next step.**
- **Aug 11**: full dry run in the same time slot (18:30–21:30h) — EventBridge Scheduler fires it on its own now; freeze code afterward.
- **Aug 12 (D-day)**: monitoring only, no code changes during the event.

## Operational tooling

- `terraform/` — AWS + archive + null provider (`main.tf`), variables (`variables.tf`), mandatory budget alarm (`budget.tf`, decision 5), per-source IAM roles (`iam.tf`, decision 7), data lake bucket (`s3.tf`), one Lambda per source (`lambda_ree.tf`, `lambda_aemet.tf`, `lambda_dgt_traffic.tf`, `lambda_dgt_camera.tf` — includes the Pillow layer, `lambda_trends.tf`), EventBridge Scheduler (`scheduler.tf`). Local state, no remote backend (solo project).
- `admin.sh` — single entrypoint for infra + ops. Works with AWS CLI v1 and v2 (auto-detects version). Centralized source registry (name → Lambda function); adding a new source = one line in the registry.
  - Infra: `init`, `plan`, `deploy`, `destroy` (asks for explicit typed confirmation), `status`.
  - Ops: `invoke <source>`, `invoke-all`, `logs <source> [mins]`, `cost`, `dry-run`.
  - Registered sources: `ree`, `aemet`, `dgt_traffic`, `trends`, `dgt_camera`.
  - `local [source]` — offline mode, no network/AWS: runs a source's (or all 5) `handler()` with `fetch()` mocked against `lambdas/<source>/fixtures/sample_response.json`, validates the result against the unified schema. Details in `scripts/local_dev.py`.
  - **Important**: `dry-run`/`invoke` make real calls to AWS and external APIs. Use carefully on Trends (Google block risk). For fast iteration during development, use `local` instead.
- `lambdas/` — code for the 5 sources (`<source>/handler.py` + `fixtures/`), shared schema (`common/envelope.py`), and shared S3 writer (`common/s3_writer.py`, partitioned ndjson). All 5 `fetch()` functions catch their own errors and degrade to 0 records instead of taking down the Lambda. `scripts/local_dev.py` — harness for the `local` mode above.

## Current status (handoff for a new chat session)

- AWS account `879381241577` (alias `andrew-aws123`), Paid plan, region `eu-west-1`. Operating user: `andrew` (group `admin`, `AdministratorAccess`) — never root.
- **Infra fully deployed** (`terraform apply` applied, nothing pending): budget, 5 IAM roles + policies, bucket `eclipse2026-data-lake`, 5 Lambdas, Pillow layer, 16 EventBridge Scheduler schedules, Glue Catalog (`eclipse2026_db.events`), Athena workgroup (`eclipse2026-wg`).
- **All 5 sources tested live** with `./admin.sh invoke <source>` — real data confirmed in S3 (`source=<X>/dt=2026-08-09/hour=.../*.json`) for all 5. Per-source detail in "Data sources" above; build history for each in CHANGELOG.md (2026-08-09).
- **Glue/Athena layer tested live**: `SELECT ... FROM eclipse2026_db.events WHERE dt='2026-08-09'` returns real rows across sources (`ree`, `dgt_camera` confirmed) via partition projection, no crawler/MSCK needed. Note: raw `aws athena`/`aws glue` CLI calls need `--region eu-west-1` explicitly (CLI default profile region is `us-east-1`); `admin.sh`/terraform already pin the right region via `var.aws_region`.
- EventBridge Scheduler deployed but **inert until 2026-08-11 16:30 UTC** (18:30 local) — nothing needs manual invoking until then, the scheduler fires the dry run and the event on its own.
- Current cost: ~$0 (see `./admin.sh cost`). Nothing with a fixed hourly cost deployed; Athena is pay-per-scan with a 1 GiB/query cap.
- **Immediate next step — this is the phase this new session is for**: minimal dashboard (QuickSight vs. homemade) over the `events` table. Ingestion + catalog + query layers are done.
- Pending, not blocking the above: sub-minute camera cadence, dashboard scope, rotate `andrew`'s access key — see "Still to decide".

Change history: see [CHANGELOG.md](CHANGELOG.md).
