# Python test suite

Unit tests for the functional core (`src/curia_core/`) and the four lambda handlers
(`apps/`). Everything runs offline: no AWS account, no credentials, no network, no Docker.

## Running

The quickest way is the repo-wide runner, which does Python and Dart together:

```bash
./scripts/run_tests.sh            # both suites, with coverage gates
./scripts/run_tests.sh python     # this suite only
./scripts/run_tests.sh --no-coverage
```

Or drive pytest directly from the repo root (config lives in `pytest.ini`, so no flags
are needed — `pythonpath`, `testpaths` and the coverage gate are all set there):

```bash
./.venv/bin/python -m pytest                      # all tests + coverage report
./.venv/bin/python -m pytest -v                   # one line per test
./.venv/bin/python -m pytest tests/test_stats.py  # one module
./.venv/bin/python -m pytest -k majority_baseline # by name
./.venv/bin/python -m pytest --no-cov             # skip the coverage run
```

First-time setup:

```bash
python3 -m venv .venv
./.venv/bin/pip install -r requirements-dev.txt
```

## Coverage

`pytest.ini` measures `src/curia_core` and `apps`, and fails the run below **70%**.
Current coverage is **98%** across 634 statements.

## Layout

| File | Covers |
|------|--------|
| `conftest.py` | Fixtures and synthetic-data builders; the in-memory `StubS3` |
| `test_schemas.py` | Field-name constants and both JSON schemas |
| `test_io.py` | The local-vs-S3 switch, both branches, and schema validation |
| `test_readers.py` | `.json` / `.csv` / `.xlsx` dispatch, LAD column detection |
| `test_deprivation.py` | LSOA→LAD aggregation, rank→percentile rebasing, deltas |
| `test_election.py` | Seat counts, the majority-flip `change_factor`, absent councils |
| `test_joining.py` | Fuzzy council↔LAD matching and name normalisation |
| `test_ingestion_pipeline.py` | Full ingestion run end to end against tmp dirs |
| `test_features.py` | Feature matrix, degenerate-column guard, z-scoring, PCA |
| `test_cluster.py` | Silhouette k selection and the KMeans refit |
| `test_stats.py` | Cluster summaries, significance, importance, REQ_4 scoring |
| `test_ml_pipeline.py` | Full clustering run, `change_factor_cluster`, schema validity |
| `test_predict.py` | Common indices, the held-out split, the no-ML baseline, write-back |
| `test_handlers.py` | All four lambda handlers, including the files API |

## How the AWS surface is handled

Nothing is mocked with `moto` — the AWS surface this project touches is four S3 calls, so
a hand-written stub is smaller, faster and has no extra dependency.

- **`curia_core.common.io`** imports `boto3` lazily inside `_s3()`. The `stub_s3` fixture
  replaces that function with an in-memory `StubS3`, so **both** the local and the AWS
  branch of every IO function are covered without boto3 being installed at all.
- **`apps/files_api/app.py`** imports `boto3` at module scope and creates a client on
  import. The `files_api` fixture puts a stub module into `sys.modules` before loading the
  handler from its path, so the pagination, presigning, 401/404/500 paths are all covered.
- **The three container-image handlers** are thin wrappers; each is tested by stubbing the
  core function it delegates to.

## Deliberately not covered

| Area | Why |
|------|-----|
| `infra/` (CDK stacks) and `app.py` | Synthesising the stack runs `DockerImageCode.from_image_asset` for three lambdas, which needs a working Docker daemon and builds real images. That is an integration concern, not a unit test. Validate with `cdk synth` in an environment that has Docker. |
| `tools/*.py` | Thin local runners over the same core functions the tests already exercise; `tools/test_all.py` is itself the end-to-end check, run against the real data files. |
| Real AWS behaviour (IAM, S3 eventing, presigned URL validity) | Requires a deployed environment. |

For the end-to-end check against the real datasets, run:

```bash
CURIA_LOCAL=true ./.venv/bin/python tools/test_all.py
```
