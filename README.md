# Eclipse 2026 — Live data pipeline for Spain's total solar eclipse

**[→ Live dashboard](https://anverpy.github.io/eclipse2026/)**

On **August 12, 2026**, a total solar eclipse crosses mainland Spain along a narrow band from A Coruña to Palma de Mallorca — the first one visible from Spain in decades. This project pulls together five independent public data sources along that path and republishes them as a free, live public dashboard, built end-to-end as a data engineering portfolio project on AWS.

It's not trying to be the most sophisticated pipeline possible — the explicit design priority, end to end, was **minimum cost**. The whole thing is built to run its one live event day for a few dollars, on a serverless, pay-per-use architecture, with a hard budget alarm from day one.

## What it tracks

Five public data sources, all served from the project's own infrastructure (never proxied live from the original APIs):

| Source | What | Why it's here |
|---|---|---|
| ⚡ **REE** (Red Eléctrica de España) | Real-time solar photovoltaic generation, mainland Spain | Should visibly dip during totality — the "hero" metric |
| 🌡️ **AEMET** (Agencia Estatal de Meteorología) | Temperature at 10 stations along the totality path | The eclipse cools the air measurably as the sky darkens |
| 🚦 **DGT Tráfico** (Dirección General de Tráfico) | Active road incidents, official national feed | People pull over to watch — does traffic behavior show it? |
| ☀️ **DGT Cámaras** (Dirección General de Tráfico) | Mean brightness from 9 official highway cameras | The most direct read on the sky actually darkening |
| 🔍 **Google Trends** | National search interest for "eclipse" | Public attention, before/during/after |

Coverage is limited to the 10 cities along the totality path plus mainland Spain and Palma — it's not a nationwide dataset, by design.

## How it's built

```
5 sources → Lambda (fetch + normalize) → S3 (partitioned data lake)
                                            │
                                            ├── Glue Catalog + Athena (ad-hoc SQL queries)
                                            │
                                            └── aggregator Lambda → public S3 bucket → GitHub Pages dashboard
```

- **Ingestion**: one AWS Lambda per source, each polling on its own schedule via **EventBridge Scheduler**, writing directly to S3 as partitioned newline-delimited JSON. No Kinesis/Firehose/DynamoDB — a live event with a few dozen readings a minute doesn't need a streaming platform, and every extra moving part is extra cost and extra risk on event day.
- **Cadence** tightens automatically during totality (as low as ~20s for the two highest-signal metrics — camera brightness and the dashboard snapshot) and goes fully dormant outside two bounded windows: an Aug 11 dry run and the real Aug 12 event.
- **Storage & query**: S3 as the data lake, cataloged in Glue with **partition projection** (no crawler needed — the schema and partitioning scheme are fixed upfront), queryable ad-hoc through Athena with a scanned-data cap as a cost guardrail.
- **Public dashboard**: a small `aggregator` Lambda distills the raw data into a lightweight public JSON snapshot, republished to a dedicated public S3 bucket every couple of minutes. The dashboard itself is a single self-contained HTML file — no frameworks, no build step, hand-rolled SVG charts — served for free on GitHub Pages.
- **Infrastructure as code**: the entire stack (Lambdas, IAM roles, S3, Glue, Athena, EventBridge schedules, budget alarm) is defined in Terraform, so it can be stood up or fully torn down with one command.

## Repo layout

```
terraform/    infrastructure as code — every AWS resource used by the project
lambdas/      one folder per data source, plus shared schema/S3-writer code
docs/         the public dashboard (docs/index.html), served via GitHub Pages
admin.sh      single entrypoint for infra + day-to-day ops (see below)
CHANGELOG.md  build history and notable decisions, in chronological order
```

## Running it locally

The dashboard is a static file — no build step:

```bash
./admin.sh preview          # serves docs/ at http://localhost:8000
```

The ingestion Lambdas can also run fully offline against saved fixture data, with no AWS credentials or network access required:

```bash
./admin.sh local             # runs all 5 sources against fixtures, validates the schema
./admin.sh local ree         # or just one source
```

## What's deliberately out of scope

**Emergency room admissions.** Early on, ER admission data (by triage level, reason, hospital) looked like a compelling metric to correlate against the eclipse — but no source in Spain publishes that in real time, for the obvious reason that it's protected health data. The one open-data portal that does publish something close (Castilla y León, which sits on the totality path) only releases it **monthly**, so it can't be part of a live pipeline.

Rather than drop the idea entirely, the plan is to publish a short follow-up report once that portal's data for August lands — around the **end of the month** — looking specifically at admissions on eclipse day. That'll be a separate, retrospective piece of analysis, not part of the live dashboard above.

## Data sources & credit

- Electricity generation: [REE ESIOS](https://www.esios.ree.es/)
- Weather: [AEMET OpenData](https://opendata.aemet.es/)
- Traffic incidents & cameras: [NAP-DGT](https://nap.dgt.es/) (Punto de Acceso Nacional, Dirección General de Tráfico)
- Search interest: Google Trends
- Totality-path map & phase-progression reference images: [Instituto Geográfico Nacional](https://astronomia.ign.es/eclipses-de-sol-y-luna/eclipse-total-sol-de-12-de-agosto-2026)

Full build history and design decisions are in [CHANGELOG.md](CHANGELOG.md).
