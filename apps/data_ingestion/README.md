# data_ingestion

Joins UK deprivation data with local-election results into one per-Local-Authority-District
(LAD) dataset. First stage of the pipeline.

| | |
|---|---|
| **Type** | Container-image Lambda (`DockerImageFunction`) |
| **Trigger** | Manual invoke (AWS console / CLI) — the ingestion step is run once per comparison pair |
| **Handler** | `app.lambda_handler` → `curia_core.ingestion.pipeline.run(event)` |
| **Core module** | `src/curia_core/ingestion/` (`readers`, `deprivation`, `election`, `joining`, `pipeline`) |
| **Memory / timeout** | 2048 MB / 5 min |
| **Runtime deps** | pandas, openpyxl, rapidfuzz, jsonschema (`requirements.txt`) |

## Input event
```json
{
  "deprivation_file_start": "2015_dep.json",
  "deprivation_file_end":   "2019_dep.json",
  "local_election_start":   "opencouncildata_councillors_2018.csv",
  "local_election_end":     "opencouncildata_councillors_2022.csv"
}
```
File names reference objects in the input bucket (or, locally, files under `data/`).

## What it does
1. Reads each file (`.xlsx / .json / .csv`), detecting the LAD-name column by prefix.
2. Aggregates LSOA-level deprivation to LAD level (mean of each of the 16 rank/decile fields),
   then computes deltas (`start − end`).
3. Counts council seats per party per year and sets **`change_factor` = 1 if the majority
   party flipped, else 0**; also emits per-party seat deltas.
4. Fuzzy-matches council ↔ LAD names; unmatched/ambiguous names are logged.
5. Validates every entry against the ingestion schema.

## Outputs (bucket prefix `output/`)
- `deprivation-election-data-<key>.json` — the joined dataset (triggers the ML pipeline).
- `unused-deprivation-election-data-<key>.log` — unmatched councils/LADs and dropped entries.

`<key>` = `d_<depStart>_d_<depEnd>_le_<elecStart>_le_<elecEnd>`.

## Environment
| Var | Purpose |
|-----|---------|
| `INPUT_BUCKET` | source of input files (AWS mode) |
| `OUTPUT_BUCKET` | destination for outputs |
| `CURIA_LOCAL` | if truthy, read/write local `data/` + `local_output/` instead of S3 |

IAM: read on the input bucket, read/write on the output bucket.

## Run locally
```bash
CURIA_LOCAL=true ./.venv/bin/python tools/run_ingestion_local.py       # both pairs (or pass 1 / 2)
```
The `PAIRS` dict in `tools/run_ingestion_local.py` holds the two canonical event payloads.
