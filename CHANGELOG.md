# Changelog

Project change and fix history. The living technical plan is in [README.md](README.md); this just keeps the history so minor updates don't bloat the README.

## 2026-08-09

### Added
- **All 5 sources deployed and tested live against real AWS** (not just `local`): each Lambda actually invoked, data confirmed in S3 (`eclipse2026-data-lake`).
  - REE: ESIOS indicator `1295` ("Generación T.Real Solar fotovoltaica", geo_id 8741 Peninsula, ~5min resolution) — found by listing `GET /indicators` and comparing candidates (`1161` "Generación medida" returned 0 values, looks discontinued).
  - AEMET: personal key received, two-step flow implemented, 10 curated stations along the totality path (one per city, out of ~10k total stations).
  - DGT traffic: NAP-DGT turned out to be **public with no registration** for the DATEX2 feeds (incidents 1min, cameras 1h) — the NAP-DGT key/account that was hard to find wasn't actually needed. Metric redefined from "intensity" (no public real-time traffic-volume feed exists on NAP-DGT) to "active incident" (DATEX2 incident presence, filtered to totality-path provinces).
  - DGT cameras: 9 curated cameras (one per totality-path province), public JPG image via the DATEX2 catalog's `deviceUrl`, mean brightness via Pillow. Pillow packaged as a Lambda layer (manylinux wheel via `pip --platform`, no Docker).
  - Trends: implemented without `pytrends` — the same 3-call flow it wraps (cookie from `trends.google.com` + `api/explore` + `api/widgetdata/multiline`) done by hand with `urllib`, to avoid an extra layer. Confirmed that without a browser User-Agent Google blocks immediately with a 429; with a real browser UA it works.
- Final ingestion pattern for all 5 sources: **Lambda → S3 direct**, no Kinesis or DynamoDB (simplicity and cost over real-time "hero" streaming — decision 8).
- Terraform: `s3.tf` (data lake bucket), `lambda_<source>.tf` (one per source), `scheduler.tf` (EventBridge Scheduler). `lambdas/common/s3_writer.py` (partitioned ndjson write, shared by all 5).
- EventBridge Scheduler deployed: 16 schedules bounded by `start_date`/`end_date` to **2026-08-11** (dry run) and **2026-08-12** (event) only, same 18:30–21:30 local window both days. Two-tier cadence (normal + tighter in the 20:15–20:45 totality sub-window) for `ree`, `dgt_traffic`, `dgt_camera`; flat cadence for `aemet` (10min) and `trends` (20min).
- Hardened error handling across all 5 sources: `fetch()` never lets a network/API failure take down the invocation — catches, logs, and returns empty, so a one-off live failure just skips a cycle instead of failing the Lambda.
- Glue Data Catalog + Athena deployed and verified live: `terraform/glue.tf` (database `eclipse2026_db`, single table `events`), `terraform/athena.tf` (workgroup `eclipse2026-wg`, results bucket, 1 GiB/query scanned cap). No Crawler — schema is fixed (matches `envelope.py`) and partitions (`source`/`dt`/`hour`) resolved via **partition projection**, so no crawler run or MSCK REPAIR is ever needed and the catalog can't drift from the actual S3 keys. `raw` typed as `string` (not `struct`) since its shape differs per source — OpenX JsonSerDe auto-serializes the nested object into that column, query with `json_extract()`. Verified with a live `SELECT ... WHERE dt='2026-08-09'` returning real `ree`/`dgt_camera` rows.

### Fixed
- `admin.sh` assumed AWS CLI v2 (`--cli-binary-format`, `AWS_REGION` variable); the user has CLI v1, which recognizes neither. Now detects the version and falls back to `AWS_DEFAULT_REGION`.
- `terraform apply` had never actually completed: the budget was left `tainted` and the 5 inline IAM policies never got created on the first attempt. Fixed by applying together with the rest of the new infra.
- Raw `aws athena`/`aws glue` CLI calls silently hit the wrong region (`WorkGroup is not found`) — CLI default profile region is `us-east-1`, project is `eu-west-1`. Not a code bug (Terraform/`admin.sh` already pin `var.aws_region` correctly), just a gotcha for manual CLI queries — pass `--region eu-west-1` explicitly.
- Public live dashboard built and deployed: `terraform/aggregator.tf` (periodic Lambda, own IAM role, reads all 5 source prefixes directly from S3 rather than Athena — deterministic runtime for a tight refresh cadence, no per-invoke query cost/latency) + `terraform/public_site.tf` (dedicated `eclipse2026-public` bucket, public read scoped to the single `latest.json` object only, CORS locked to the GitHub Pages origin). `raw` dropped from the public payload; a `label` field (station city / province) is extracted from `raw` during aggregation instead, since AEMET/DGT station/camera IDs are opaque codes on their own. Frontend at `docs/index.html` — single self-contained file, hand-rolled SVG charts (no chart library dependency), dark astronomical theme, hero chart is mean camera brightness with a totality-window band annotation (expected to visibly dip during totality, same for REE solar generation). Chose GitHub Pages over QuickSight: QuickSight needs a recurring per-author subscription (at odds with the project's pay-per-use cost goal) and the project needed to be public anyway.
- Repo published public: [github.com/anverpy/eclipse2026](https://github.com/anverpy/eclipse2026), dashboard live at [anverpy.github.io/eclipse2026](https://anverpy.github.io/eclipse2026/). `terraform.tfvars`/`.tfstate`/`.terraform/` were already gitignored (real ESIOS/AEMET tokens confirmed never staged); excluded a local `assets/` folder (reference images + scraped text, not ready for the public repo) and a stray Kate editor swap file.

### Known issues
- Camera cadence during totality capped at 1min (EventBridge Scheduler's `rate()` floor) instead of the original 10–15s from the README — would need a Lambda with an internal loop or Step Functions. Evaluate after the dry run if 1min is insufficient.
- Trends remains the fragile link: unofficial API, real risk of live blocking (already saw a 429 during testing). Designed to degrade to 0 records without taking down the rest of the pipeline if it happens on event day.
- `andrew`'s access key still unrotated since 2026-03-09 (see README).

## 2026-08-08

### Added
- Personal ESIOS API token received from REE (`consultasios@ree.es`). Stored in `terraform/terraform.tfvars` (gitignored) as a `sensitive` variable (`terraform/variables.tf`), with `terraform/terraform.tfvars.example` as a secret-free template for the public repo.
- Local dev mode with no network/AWS: `lambdas/<source>/handler.py` + `fixtures/sample_response.json` for all 5 sources, shared schema/validation in `lambdas/common/envelope.py`, harness `scripts/local_dev.py` (`list` / `run` / `run-all`) wired into `./admin.sh local [source]`.
- Root `.gitignore` (`__pycache__/`, `*.pyc`).

### Fixed
- AWS account security review: confirmed root has no access keys and MFA is active; `andrew`'s console password reset (the old one was invalid/unknown); `andrew`'s MFA recreated from scratch after a broken virtual device (`i13`) that never got to validate codes.

### Known issues
- `andrew`'s access key active since 2026-03-09 without rotation — pending decision on whether to rotate before closing out the project (see README, "Still to decide").

## 2026-08-07

### Added
- First draft of the technical plan (`README.md`): data sources, unified schema, AWS architecture, key decisions.
- AWS account created (Paid plan over Free, to avoid mid-project service restrictions), operating IAM user `andrew` (group `admin`, `AdministratorAccess`).
- `terraform` installed via `pacman` (`extra` repo, no AUR needed). `terraform init` and `terraform plan` run and validated — 11 resources (budget + 5 IAM roles + 5 inline policies).
- Decision: IaC in Terraform (not CDK/SAM); one Lambda execution role per source instead of a shared one.
