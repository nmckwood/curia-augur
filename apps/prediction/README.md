# prediction

Cross-analysis prediction step (REQUIREMENTS_3): tests whether deprivation-change indices can
predict a change of majority party, using an honest held-out split. Third stage.

| | |
|---|---|
| **Type** | Container-image Lambda (`DockerImageFunction`) |
| **Trigger** | S3 `ObjectCreated`, prefix `analysis/`, suffix `.json` (an ML analysis output) |
| **Handler** | `app.lambda_handler` → `curia_core.ml.predict.run(...)` |
| **Core module** | `src/curia_core/ml/predict.py` |
| **Memory / timeout** | 3008 MB / 5 min |
| **Runtime deps** | numpy, scikit-learn, scipy, jsonschema (`requirements.txt`) |

## What it does
Requires **both** analyses to exist (it joins them), so the handler:
1. Lists all `analysis/*.json`; if fewer than 2, it exits.
2. **Loop guard** — if every analysis already has `meta.key_indices` and each constituency has
   the prediction field, it exits without writing (its own writes re-fire this event, so this
   is what stops the cascade).
3. Otherwise runs `predict.run` over all analyses.

`predict.run` — all selection and fitting on a **stratified train split**, accuracy on the
**held-out test split** (no feature-selection leakage):
- selects each year's top indices by |standardized logistic coefficient| on train;
- **common-indices model** = intersection across years → `change_factor_deprivation_key_indices`;
- **per-year best-indices model** → `change_factor_per_year_key_indices`;
- per-index univariate held-out accuracy + a majority-class **baseline**.

## Output
Each `analysis/analysis-<key>.json` is augmented in place with `meta.key_indices`,
`meta.prediction` (held-out / baseline / per-year accuracies, `per_year_index_details`), and the
two per-constituency prediction fields.

## Environment
| Var | Purpose |
|-----|---------|
| `OUTPUT_BUCKET` | reads/writes the analysis + ingestion objects |
| `CURIA_LOCAL` | if truthy, use `local_output/` instead of S3 |

IAM: read/write on the output bucket.

## Run locally
```bash
# after both analyses exist (tools/test_all.py or run_ml_local.py):
CURIA_LOCAL=true ./.venv/bin/python tools/run_prediction_local.py
```
