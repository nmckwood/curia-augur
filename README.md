# Curia Augur

Curia Augur investigates a single question:

> **Can deprivation indices predict whether a UK local authority changes its voting behaviour?**

It ingests government deprivation data and local-election results, clusters local authorities
by how their deprivation changed between two censuses, and tests whether those deprivation
changes predict a change in the majority party. It is a cost-optimized, serverless
**AWS CDK (Python) backend + Flutter web UI**, with a functional core that runs identically
locally and in AWS.

> **Headline finding:** deprivation-change indices do **not** meaningfully predict a change of
> the majority party. See [Findings](#findings).

---

## Table of contents
- [Architecture](#architecture)
- [Pipeline stages](#pipeline-stages)
- [Repository layout](#repository-layout)
- [Data](#data)
- [The functional core & local/AWS parity](#the-functional-core--localaws-parity)
- [Running locally (no AWS)](#running-locally-no-aws)
- [The Flutter UI](#the-flutter-ui)
- [Deploying to AWS](#deploying-to-aws)
- [Output schemas](#output-schemas)
- [Methodology & key decisions](#methodology--key-decisions)
- [Findings](#findings)
- [Testing](#testing)
- [Conventions](#conventions)

---

## Architecture

```
data/ (raw xlsx/csv/geojson)
        │  tools/upload_data_to_s3.py
        ▼
   S3 input bucket
        │  data_ingestion lambda (container)  — manual invoke, event = 4 filenames
        ▼
   S3 output/deprivation-election-data-<key>.json   (+ unused-...log)
        │  S3 ObjectCreated (prefix output/)
        ▼
   ml_pipeline lambda (container)
   z-score → KMeans(k=2..14, silhouette) → cluster scoring → feature importance → PCA(2d)
        ▼
   S3 analysis/analysis-<key>.json
        │  S3 ObjectCreated (prefix analysis/)
        ▼
   prediction lambda (container)  — cross-analysis, loop-guarded
   common indices + per-year best indices → held-out prediction of change_factor
        ▼
   S3 analysis/analysis-<key>.json  (augmented in place)
        │  files_api lambda (GET, Cognito-secured) → presigned URLs
        ▼
   Flutter web UI (CloudFront + private S3)
```

Composite key format: `d_<depStartYr>_d_<depEndYr>_le_<elecStartYr>_le_<elecEndYr>`,
e.g. `d_2015_d_2019_le_2018_le_2022`.

---

## Pipeline stages

### 1. Data ingestion (`src/curia_core/ingestion/`)
Input event (REQUIREMENTS §Data-Ingestion-3):
```json
{
  "deprivation_file_start": "2015_dep.json",
  "deprivation_file_end":   "2019_dep.json",
  "local_election_start":   "opencouncildata_councillors_2018.csv",
  "local_election_end":     "opencouncildata_councillors_2022.csv"
}
```
- **readers.py** — reads `.xlsx / .json / .csv`; detects the Local-Authority-District-name
  column by prefix, ignoring the varying `(2013)/(2019)/(2024)` year suffix.
- **deprivation.py** — deprivation JSON is LSOA-level (~33k rows); group by LAD, **mean** each
  of the 16 rank/decile fields, then delta = `start − end`.
- **election.py** — election CSV is one row per councillor; seat count = rows per
  `(council, party)`; **`change_factor` = 1 if the majority (most-seats) party changed between
  the two years, else 0** (REQUIREMENTS_2). Per-party seat deltas are also emitted.
- **joining.py** — fuzzy-matches council ↔ LAD names (rapidfuzz, difflib fallback; normalized,
  stop-words stripped). Unmatched/ambiguous names are written to the `unused-...log`.
- **pipeline.py** — orchestrates, validates every entry against the schema, writes
  `output/deprivation-election-data-<key>.json` + `output/unused-deprivation-election-data-<key>.log`.

### 2. ML pipeline (`src/curia_core/ml/`) — triggered by S3 write to `output/`
- **features.py** — 16 rank+decile deltas as the feature matrix, z-score normalized; `pca_2d`
  for a 2-component projection used by the cluster scatter.
- **cluster.py** — KMeans for `k` in `K_RANGE` (currently 2..14), pick best `k` by silhouette.
- **stats.py** — per-cluster mean/median `change_factor`; flags
  the high-change cluster; ranks feature importance by |high-change mean − others mean|; scores
  each cluster's implied prediction (`change_factor_cluster`) against the actual outcome and
  ranks the clusters by accuracy (REQUIREMENTS_4).
- **pipeline.py** — assembles + validates `analysis/analysis-<key>.json`.

### 3. Cross-analysis prediction (`src/curia_core/ml/predict.py`) — triggered by S3 write to `analysis/`
Runs once both analyses exist (loop-guarded so it no-ops after augmenting). **All feature
selection and model fitting happen on a stratified train split; accuracy is measured on the
held-out test split**, so there is no feature-selection leakage.
- **Common-indices model** (REQUIREMENTS_3): intersect each year's train-selected top indices,
  fit LogisticRegression on those, predict every constituency
  (`change_factor_deprivation_key_indices`).
- **Per-year best-indices model**: each year's own top-K indices (ranked by |standardized
  logistic coefficient| on train) → `change_factor_per_year_key_indices`.
- **Per-index univariate accuracy** + **majority-class baseline** so predictiveness is judged
  against the "predict no change" bar. The baseline is reported as
  `meta.prediction.baseline` — `{majority_class, holdout_accuracy, all_accuracy,
  n_correct_all, n_total_all}` — the "if you did no ML at all and just guessed the most
  common `change_factor`" number the UI shows beside every accuracy pie.

### 4. Files API (`apps/files_api/`)
Cognito-secured `GET /files` → array of `{filename, pre_signed_url}` for every analysis output.

### 5. UI — see [The Flutter UI](#the-flutter-ui).

---

## Repository layout

```
curia-augur/
├── app.py                       # CDK app entry (context: account/region/root_domain/subdomain)
├── cdk.json                     # "app": "python3 app.py"
├── requirements.txt             # CDK deps
├── requirements-dev.txt         # pipeline + local deps (pandas, sklearn, scipy, rapidfuzz, …)
├── infra/
│   ├── domain_stack.py          # looks up your existing hosted zone; ACM certs
│   └── resources_stack.py       # buckets, container lambdas, S3 events, Cognito, API GW, CloudFront
├── src/curia_core/              # PURE functional core (imported by lambdas AND tools)
│   ├── common/{io,schemas}.py   # CURIA_LOCAL IO switch + jsonschema; field constants + schemas
│   ├── ingestion/{readers,deprivation,election,joining,pipeline}.py
│   └── ml/{features,cluster,stats,pipeline,predict}.py
├── apps/                        # thin lambda handlers + Dockerfiles
│   ├── data_ingestion/  ml_pipeline/  prediction/   # container images (sklearn/pandas)
│   └── files_api/               # zip lambda (boto3 only)
├── tools/
│   ├── upload_data_to_s3.py     # push data/ to the input bucket
│   ├── run_ingestion_local.py   # PAIRS definitions + local ingestion
│   ├── run_ml_local.py          # local ML
│   ├── run_prediction_local.py  # local cross-analysis prediction
│   ├── test_all.py              # end-to-end local runner + assertions (REQ General-12)
│   ├── prepare_local_ui_assets.py  # copy+simplify outputs into the Flutter asset bundle
│   ├── simplify_geojson.py      # dependency-free GeoJSON simplifier (RDP + rounding)
│   ├── deploy_web.sh            # flutter build web + S3 sync + CloudFront invalidation
│   └── convert_xlsx_to_json.py  # one-off deprivation xlsx → json helper
├── frontend/curia_augur_ui/     # Flutter web app
├── tests/test_core.py           # unit tests
├── docs/                        # REQUIREMENTS*.md + FLUTTER_WSL_SETUP.md
├── data/                        # raw inputs (deprivation, election, geospatial)
└── CLAUDE.log                   # append-only session log (project convention)
```

---

## Data

| Set | Location | Shape |
|-----|----------|-------|
| Deprivation | `data/deprivation_data/{2015,2019,2025}_dep.json` | LSOA-level (~33k rows), 16 rank/decile fields |
| Local elections | `data/local_election_data/opencouncildata_councillors_{2018,2022,2026}.csv` | one row per councillor |
| Geospatial | `data/geospatial_data/*.geojson` (2022, 2025 boundaries) | UI only; ~200–280 MB raw |

**Comparison pairs** (REQUIREMENTS §11):
- 2015→2019 deprivation vs 2018→2022 election (2018 benchmark).
- 2019→2025 deprivation vs 2022→2026 election (2022 benchmark).

The UI maps each analysis to the nearest boundary set (2022 analysis → 2022 boundaries;
2026 analysis → 2025 boundaries).

> The raw BFC GeoJSON is far too large to bundle/serve as-is; `tools/simplify_geojson.py`
> reduces each to ~2.3 MB (Ramer–Douglas–Peucker + coordinate rounding, all features/names
> preserved). Both `prepare_local_ui_assets.py` and `deploy_web.sh` run it automatically.

---

## The functional core & local/AWS parity

`src/curia_core/` contains **all** logic as pure functions. The lambda handlers in `apps/*/app.py`
are one-line wrappers, and the `tools/` scripts import the same modules — so the exact code
that runs in AWS runs locally. IO is switched by the **`CURIA_LOCAL`** environment flag
(`common/io.py`): when set, reads/writes go to `data/` and `local_output/` instead of S3.

---

## Running locally (no AWS)

```bash
python3.11 -m venv .venv
./.venv/bin/pip install -r requirements-dev.txt

# End-to-end: ingestion → ML → cross-analysis prediction for both pairs, with assertions.
CURIA_LOCAL=true ./.venv/bin/python tools/test_all.py

# Unit tests
./.venv/bin/python -m unittest tests.test_core -v
```
Outputs land in `local_output/output/` and `local_output/analysis/`. Individual stages:
```bash
CURIA_LOCAL=true ./.venv/bin/python tools/run_ingestion_local.py    # both pairs (or pass 1 / 2)
CURIA_LOCAL=true ./.venv/bin/python tools/run_ml_local.py
CURIA_LOCAL=true ./.venv/bin/python tools/run_prediction_local.py
```

---

## The Flutter UI

`frontend/curia_augur_ui/` — Flutter 3.32 / Dart 3.8. Build config via `--dart-define`.

**Main page** — one scrolling page (permanent scrollbar down the right) per selected analysis
file. Above it sits the interpretation banner carrying the ecological-fallacy caveats. Below
the analysis dropdown are four cards (REQUIREMENTS_5):

1. **Summary** — a plain-English readout of *both* models: how many clusters k-means found, the
   high-change cluster's flip rate against the rest, each cluster scored as a predictor, then
   the logistic regression's held-out accuracy read against the no-ML baseline. Ends with the
   indices that most characterize the high-change cluster.
2. **K-means** — two OpenStreetMap (`flutter_map`) choropleths with hover tooltips and legends:
   the actual election result, and the cluster prediction (`change_factor_cluster`). Both use
   the same encoding — orange + dashed outline for a change, blue + solid for no change — so any
   authority the clustering got wrong shows as a colour flip between the two maps. Beneath them,
   a **PCA cluster scatter** (colour *and* marker shape per cluster) and a **correctness pie**.
3. **Logistic regression** — held-out **accuracy pie**, the **no-ML baseline** beside it for
   contrast, and a written **regression summary** giving the uplift over that baseline.
4. **Local authority data** — full-width collapsible, filterable table: one row per authority
   with `deprivation` flattened to a column per index, plus the PCA coordinates and each
   model's prediction. Scrolls horizontally, since the columns are wider than any window.

Outline and marker shape carry every binary distinction alongside hue, so nothing depends on
colour alone (WCAG 2.2 SC 1.4.1); the data table is the text equivalent of the maps and charts.

> The per-year predictiveness page (`lib/screens/per_year_screen.dart`) is no longer linked from
> the UI — REQUIREMENTS_5 dropped it. The source and its tests remain in the tree.

**Run flags** (`lib/config.dart`):

| dart-define | effect |
|-------------|--------|
| `LOCAL=true` | fully offline: file list + analyses + GeoJSON from bundled assets, no API/auth |
| `LOCAL_FILENAME=<file>` | preselect one bundled analysis (implies local) |
| `SKIP_AUTH=true` | skip Cognito login (dev against a local API) — never in production |
| `API_BASE_URL`, `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID` | cloud config |

```bash
# fully-local run (WSL: use web-server; open in Windows Chrome)
CURIA_LOCAL=true ./.venv/bin/python tools/test_all.py
./.venv/bin/python tools/prepare_local_ui_assets.py
cd frontend/curia_augur_ui && flutter pub get
flutter run -d web-server --web-port=8080 --dart-define=LOCAL=true
```
See `docs/FLUTTER_WSL_SETUP.md` for WSL specifics.

---

## Deploying and setting up the app

# Real deployment values (account id, bucket names, Cognito/CloudFront ids,
# seed emails and password) are kept out of version control in a local `.secret`
# file (git-ignored). Populate it from the CloudFormation outputs after deploy,
# then `source` it so the commands below can reference the variables.

```bash
pip install -r requirements.txt

# 1. Deploy the stack. Values shown are placeholders — supply your own.
#    alert_email/budget_usd wire up a monthly budget alarm (cost tripwire).
cdk deploy --all \
  --context account=<ACCOUNT_ID> --context region=<REGION> \
  --context root_domain=<ROOT_DOMAIN> \
  --context alert_email=<ALERT_EMAIL> --context budget_usd=25

# 2. Load real values from your local, git-ignored .secret file
#    (retrieve CLIENT_ID / USER_POOL_ID / DISTRIBUTION_ID from the cfn output).
set -a; source .secret; set +a

# 3. Simplify the GeoJSON boundary files (paths relative to the repo root).
python tools/simplify_geojson.py \
  --input /home/neils/curia-augur/data/geospatial_data/Local_Authority_Districts_DEC_2025_Boundaries_UK_BFC_5780731924739583250.geojson \
  --output frontend/curia_augur_ui/assets/geo/boundaries_2025.geojson \
  --tolerance 0.001 --precision 4 --min-ring-points 6

python tools/simplify_geojson.py \
  --input /home/neils/curia-augur/data/geospatial_data/Local_Authority_Districts_December_2022_UK_BFC_V2_-4534861255799681503.geojson \
  --output frontend/curia_augur_ui/assets/geo/boundaries_2022.geojson \
  --tolerance 0.001 --precision 4 --min-ring-points 6

# 4. Upload input datasets.
aws s3 cp data/deprivation_data/2015_dep.json "s3://${INPUT_BUCKET}"
aws s3 cp data/deprivation_data/2019_dep.json "s3://${INPUT_BUCKET}"
aws s3 cp data/deprivation_data/2025_dep.json "s3://${INPUT_BUCKET}"

aws s3 cp data/local_election_data/opencouncildata_councillors_2018.csv "s3://${INPUT_BUCKET}"
aws s3 cp data/local_election_data/opencouncildata_councillors_2022.csv "s3://${INPUT_BUCKET}"
aws s3 cp data/local_election_data/opencouncildata_councillors_2026.csv "s3://${INPUT_BUCKET}"

# 5. Upload boundary assets to the web bucket.
aws s3 cp frontend/curia_augur_ui/assets/geo/boundaries_2022.geojson \
  "s3://${WEB_BUCKET}/geo/boundaries_2022.geojson" --content-type application/geo+json
aws s3 cp frontend/curia_augur_ui/assets/geo/boundaries_2025.geojson \
  "s3://${WEB_BUCKET}/geo/boundaries_2025.geojson" --content-type application/geo+json

# 6. Build and deploy the web app.
WEB_BUCKET="${WEB_BUCKET}" \
  API_BASE_URL="${API_BASE_URL}" \
  COGNITO_USER_POOL_ID="${COGNITO_USER_POOL_ID}" \
  COGNITO_CLIENT_ID="${COGNITO_CLIENT_ID}" \
  DISTRIBUTION_ID="${DISTRIBUTION_ID}" \
  tools/deploy_web.sh

# 7. Provision users (self sign-up is disabled; admins create accounts).
for EMAIL in "${ADMIN_EMAIL}" "${ASSESSOR_EMAIL}"; do
  aws cognito-idp admin-create-user \
    --user-pool-id "${COGNITO_USER_POOL_ID}" \
    --username "${EMAIL}" \
    --user-attributes Name=email,Value="${EMAIL}" Name=email_verified,Value="true" \
    --message-action SUPPRESS

  aws cognito-idp admin-set-user-password \
    --user-pool-id "${COGNITO_USER_POOL_ID}" \
    --username "${EMAIL}" \
    --password "${SEED_PASSWORD}" \
    --permanent
done

{
  "deprivation_file_start": "2015_dep.json",
  "deprivation_file_end":   "2019_dep.json",
  "local_election_start":   "opencouncildata_councillors_2018.csv",
  "local_election_end":     "opencouncildata_councillors_2022.csv"
}

```

---

## Output schemas

Canonical schemas live in `src/curia_core/common/schemas.py`; every output is validated with
`jsonschema` before it is written.

---

## Data sources & attribution

This repository redistributes third-party open datasets under `data/`. Each is used under its
respective licence; please retain this attribution if you reuse the data.

| Dataset | Source | Licence |
|---------|--------|---------|
| English Indices of Deprivation (IoD 2015 / 2019) | Ministry of Housing, Communities & Local Government (now DLUHC), via GOV.UK | [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/) |
| Local councillor / election data | [OpenCouncilData](https://opencouncildata.co.uk/) | See the OpenCouncilData site for its terms (attribution required) |
| Local Authority District boundaries (GeoJSON, 2022 / 2025) | Office for National Statistics — Open Geography Portal | [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/); contains OS data © Crown copyright and database right |
| Basemap tiles | [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors | ODbL |

> Councillor names in the election data are already public record. Boundary GeoJSON is
> git-ignored (too large); download it from the ONS Open Geography Portal. Verify the current
> licence terms at each source before redistributing — they may change.

---

## Testing

One command runs everything — both suites, with coverage gates:

```bash
./scripts/run_tests.sh                # Python + Dart, coverage enforced
./scripts/run_tests.sh python         # Python only
./scripts/run_tests.sh dart           # Flutter only
./scripts/run_tests.sh --no-coverage  # faster, no coverage run
```

| Suite | Command | Tests | Coverage | Gate |
|-------|---------|-------|----------|------|
| Python (`tests/`) | `./.venv/bin/python -m pytest` | 224 | 98% | 70% |
| Dart (`frontend/curia_augur_ui/test/`) | `flutter test --coverage` | 145 | 84% | 70% |

```bash
CURIA_LOCAL=true ./.venv/bin/python tools/test_all.py
```

---

## License

Source code is released under the [MIT License](LICENSE). The bundled datasets under `data/`
are **not** covered by MIT — they remain under their original licences; see
[Data sources & attribution](#data-sources--attribution).

## Conventions

Python 3.11, snake_case, functional style for the backend; OOP for Flutter. Requirements are in
`docs/REQUIREMENTS.md`, `REQUIREMENTS_2.md`, `REQUIREMENTS_3.md`; project conventions in
`.claude/CLAUDE.md`. Each working session appends truncated `[PROMPT]/[ACTION]/[RESULT]` lines
to `CLAUDE.log`.
