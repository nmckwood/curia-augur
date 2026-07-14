# Curia Augur

Predicts whether UK local authorities change their voting behaviour based purely on
deprivation indices, using SKLearn K-Means. Serverless AWS (CDK, Python) backend + Flutter
web UI. Single environment, cost-optimized.

## Architecture

```
data/ (raw)  ──upload──▶  S3 input bucket
                              │  (manual invoke, REQ event shape)
                              ▼
                    data_ingestion lambda (container)
        joins deprivation deltas + election change per LAD
                              ▼
        S3 output/deprivation-election-data-<key>.json  +  unused-...log
                              │  (S3 ObjectCreated event)
                              ▼
                     ml_pipeline lambda (container)
      z-score → KMeans(k=2..7, silhouette) → Kruskal-Wallis → feature importance
                              ▼
                 S3 analysis/analysis-<key>.json
                              │
                 files_api lambda (GET, Cognito-secured) → presigned URLs
                              ▼
                 Flutter web UI (map + filterable table)
```

The functional core lives in `src/curia_core/` and is imported by both the lambdas
(`apps/*/app.py`) and the local runners (`tools/`), so the exact same code runs locally
and in AWS. Set `CURIA_LOCAL=true` to read/write local files instead of S3.

## Local run (no AWS needed)

```bash
python -m venv .venv && ./.venv/bin/pip install -r requirements-dev.txt
CURIA_LOCAL=true ./.venv/bin/python tools/test_all.py     # end-to-end (REQ General-12)
./.venv/bin/python -m unittest tests.test_core -v          # unit tests
```

Outputs land in `local_output/output/` and `local_output/analysis/`.

## Deploy

```bash
pip install -r requirements.txt
cdk deploy --all --context account=<acct> --context region=us-east-1
python tools/upload_data_to_s3.py --bucket curia-augur-input-<acct>
# invoke the data_ingestion lambda per comparison pair (see tools/run_ingestion_local.py
# for the two event payloads); the ML pipeline fires automatically on the S3 write.
WEB_BUCKET=... API_BASE_URL=... COGNITO_USER_POOL_ID=... COGNITO_CLIENT_ID=... \
  DISTRIBUTION_ID=... tools/deploy_web.sh
```

Deploy in `us-east-1` — the web ACM certificate must be there for CloudFront. The
`howfhowfhowf.com` hosted zone is reused (looked up, not recreated); the app is served at
`curia-augur.howfhowfhowf.com` with the API at `api.curia-augur.howfhowfhowf.com`.

## Key decisions

- **Name join**: deterministic fuzzy match (rapidfuzz, difflib fallback); unmatched names
  logged to `unused-...log`.
- **change_factor**: seats changed hands as an integer percentage (0–100) of benchmark seats.
- **LSOA→LAD**: group by Local Authority District name, mean-aggregate deciles, then delta.

See `docs/REQUIREMENTS.md` for the full spec and `.claude/CLAUDE.md` for conventions.
Every session's prompts/actions are logged to `CLAUDE.log`.
