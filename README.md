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
   z-score → KMeans(k=2..14, silhouette) → Kruskal-Wallis → feature importance → PCA(2d)
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
- **stats.py** — per-cluster mean/median `change_factor`; Kruskal-Wallis across clusters; flags
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

**Main page** (per selected analysis file):
- App banner + a dropdown of available analyses.
- A written **summary** of the indices characterizing the high-change cluster + significance.
- Three OpenStreetMap (`flutter_map`) choropleths with hover tooltips & legends:
  1. deprivation metric (selectable, green→red),
  2. actual election result changed (green = no flip / red = flip),
  3. predicted change from the common key indices.
- A **PCA cluster scatter** (clusters coloured, tooltip).
- A **predicted-vs-actual scatter** + **accuracy pie** (held-out, with baseline).
- A collapsible, filterable **data table**.

**Per-year predictiveness page** (app-bar button): since common indices don't generalize, this
page answers the per-year question — a **most-predictive-indices bar chart** (each index's
univariate held-out accuracy vs the baseline marker), plus predicted map / scatter / pie for a
model trained on that year's best indices.

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

## Deploying to AWS

Deploy in **us-east-1** (the web ACM certificate must be there for CloudFront). You supply
your own registered domain via the **required** `root_domain` context arg — it must be an
existing Route53 hosted zone you own (it is **looked up, not created**). With
`root_domain=example.com`, the app serves at `curia-augur.example.com` and the API at
`api.curia-augur.example.com` (override the subdomain with `--context subdomain=...`).

```bash
pip install -r requirements.txt
cdk deploy --all \
  --context account=<acct> --context region=us-east-1 \
  --context root_domain=<your-domain>

python tools/upload_data_to_s3.py --bucket curia-augur-input-<acct>
# Invoke the data_ingestion lambda once per comparison pair (payloads in tools/run_ingestion_local.py).
# ML fires on the output/ write; prediction fires on the analysis/ writes (loop-guarded).

WEB_BUCKET=... API_BASE_URL=https://api.curia-augur.<your-domain> \
  COGNITO_USER_POOL_ID=... COGNITO_CLIENT_ID=... DISTRIBUTION_ID=... \
  tools/deploy_web.sh
```

Cost-optimized: pay-per-use S3; container lambdas billed per invocation (rare triggers);
one-week debug log retention; no always-on compute.

---

## Output schemas

- **Ingestion** `deprivation-election-data-<key>.json` — array of
  `{ "Local Authority District name", "deprivation": {8 rank "... delta" percentile-point
  floats + 8 decile "... delta" ints},
  "local_election_results": { "council", "change_factor" (0/1), "<party>": seatDelta } }`.
- **Analysis** `analysis-<key>.json` — `meta` (k, features_used, `key_indices`, `prediction`
  {held-out/baseline/per-year accuracies, `per_year_index_details`}), `clusters`,
  `significance_test`, `feature_importance`, and `constituencies` (with `pca_x/pca_y`,
  `change_factor`, `change_factor_cluster`, `change_factor_deprivation_key_indices`,
  `change_factor_per_year_key_indices`). `meta.cluster_accuracy` holds the all-council accuracy
  of `change_factor_cluster`; `meta.degenerate_features` lists features excluded from the
  distance metric for lack of spread; each entry in `clusters` carries `predicted_change_factor`,
  `n_correct`, `accuracy` and `accuracy_rank`.

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

## Methodology & key decisions

- **Name join**: deterministic fuzzy matching (no Bedrock/semantic search — cost); unmatched
  names logged.
- **change_factor**: binary majority-party flip (REQUIREMENTS_2), superseding the earlier
  "seats changed hands %".
- **LSOA→LAD**: group by LAD name, mean-aggregate, then year delta.
- **Rank re-basing**: IoD re-ranks every edition (32,844 LSOAs in 2015/2019, **33,755** in
  2025), so raw ranks are not comparable across editions. Ranks are converted to
  within-edition national percentiles before differencing; a rank delta is a change in
  **percentile points**, not in raw rank position.
- **Abolished councils**: councils present in the benchmark year but absent from the target
  year (the Northamptonshire / Buckinghamshire / Cumbria / North Yorkshire reorganisations)
  have no successor to compare against. They are dropped and logged, not scored as
  "did not change".
- **Degenerate features**: the decile deltas mostly round to zero, and z-scoring a
  near-constant column turns its handful of non-modal rows into extreme outliers that
  dominate KMeans distance. Columns whose modal value covers ≥95% of rows are zeroed and
  listed in `meta.degenerate_features`.
- **ML features**: 16 rank+decile deltas (the decile-only signal was too weak after
  mean+round). PCA is display-only.
- **Prediction validity**: stratified train/test split; feature selection **and** fitting on
  train only; accuracy reported held-out, always against a majority-class **baseline**.
- **Two prediction models**: common-indices (tests transferable drivers) and per-year best
  indices (tests each year on its own terms).

---

## Findings

Held-out results (test split; baseline = majority-class "predict no change"):

| Analysis | Baseline | Common-indices | Per-year best | ROC AUC |
|----------|:--------:|:--------------:|:-------------:|:-------:|
| 2015→2019 / 2018→2022 | 0.779 | 0.779 | 0.767 | **0.452** |
| 2019→2025 / 2022→2026 | 0.575 | 0.517 | 0.506 | **0.445** |

- **ROC AUC ≈ 0.45 in both periods.** This is the honest headline: AUC is threshold-free
  and unaffected by class imbalance, and 0.5 is a coin flip. The features cannot rank
  councils by flip likelihood at all. Refitting with `class_weight="balanced"` forces the
  model to predict plenty of flips and makes *balanced* accuracy worse, so the near-degenerate
  output on the 2018→2022 pair is a symptom of absent signal, not of a mis-set threshold.
- **No common indices generalize** across the two periods, and neither multivariate model
  beats its baseline.

**Conclusion: deprivation-change indices do not meaningfully predict a change of majority.**

Two structural reasons, both visible in the data:

1. **The outcome is mostly national swing.** Of the 150 flips in 2022→2026, ~91 are the
   Conservatives losing — 26 of those to Reform UK, which went from 0 to 2,365 councillors.
   National swing is by definition the same everywhere, so no cross-sectional local variable
   can predict it.
2. **The predictor barely moves.** Relative deprivation is highly stable: the IMD rank delta
   has sd ≈ 2.4 percentile points over four years.

Answering the question properly would need a target that isolates *local* variation from
national swing (e.g. per-council swing measured relative to the national swing for that
party), rather than a raw majority flip.

The UI presents accuracies against the baseline so base-rate "accuracy" is not mistaken
for skill.

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
| Python (`tests/`) | `./.venv/bin/python -m pytest` | 228 | 98% | 70% |
| Dart (`frontend/curia_augur_ui/test/`) | `flutter test --coverage` | 137 | 78% | 70% |

Everything runs offline — no AWS account, credentials, network or Docker. The S3 branches
of the IO layer and the files API are covered with a small in-memory stub client rather
than `moto`. What is deliberately **not** covered, and why, is listed in
[`tests/README.md`](tests/README.md) and
[`frontend/curia_augur_ui/test/README.md`](frontend/curia_augur_ui/test/README.md) — in
short: the CDK stacks (synth needs Docker to build three lambda images), the Cognito auth
service, and `ApiService` beyond its error path.

First-time Python setup:

```bash
python3 -m venv .venv
./.venv/bin/pip install -r requirements-dev.txt
```

Separately, `tools/test_all.py` is the end-to-end check against the **real** datasets for
both comparison pairs (ingestion → ML → prediction), validating both JSON schemas and
asserting the pipeline invariants (binary `change_factor`, `change_factor_cluster` set
only in the high-change cluster, clusters ranked 1..n by accuracy, PCA coords present,
non-empty `key_indices`):

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
