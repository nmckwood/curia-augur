# ml_pipeline

Clusters Local Authority Districts by how their deprivation changed and tests whether those
clusters differ in electoral change. Second stage of the pipeline.

| | |
|---|---|
| **Type** | Container-image Lambda (`DockerImageFunction`) |
| **Trigger** | S3 `ObjectCreated`, prefix `output/`, suffix `.json` (i.e. an ingestion output) |
| **Handler** | `app.lambda_handler` → `curia_core.ml.pipeline.run(event)` |
| **Core module** | `src/curia_core/ml/` (`features`, `cluster`, `stats`, `pipeline`) |
| **Memory / timeout** | 3008 MB / 5 min |
| **Runtime deps** | numpy, scikit-learn, scipy, jsonschema (`requirements.txt`) |

## Input
An S3 event, or `{"output_key": "output/deprivation-election-data-<key>.json"}` when invoked
directly (as the local runner does).

## What it does
1. Builds the feature matrix from the **16 rank+decile deltas** and z-score normalizes it.
2. Runs KMeans for `k` in `K_RANGE` (2..14) and picks the best `k` by silhouette score.
3. Computes per-cluster mean/median `change_factor`, flags the high-change cluster, runs a
3a. Treats the clustering as a prediction: every authority in the high-change cluster gets
   `change_factor_cluster = 1`, all others 0. Each cluster is then scored on the percentage of
   its councils that call matched (`accuracy`) and ranked (`accuracy_rank`); the all-council
   figure lands in `meta.cluster_accuracy` (REQUIREMENTS_4).
4. Computes a 2-component **PCA** projection per constituency (for the UI cluster scatter).
5. Validates against the analysis schema.

## Output (bucket prefix `analysis/`)
`analysis/analysis-<key>.json` — `meta`, `clusters`, `feature_importance`,
and `constituencies` (each with `pca_x/pca_y`). Writing this triggers the `prediction` service.

## Environment
| Var | Purpose |
|-----|---------|
| `OUTPUT_BUCKET` | reads the ingestion output and writes the analysis output |
| `CURIA_LOCAL` | if truthy, use `local_output/` instead of S3 |

IAM: read/write on the output bucket.

## Run locally
```bash
CURIA_LOCAL=true ./.venv/bin/python tools/run_ml_local.py
```
