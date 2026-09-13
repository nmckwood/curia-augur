# files_api

Serves the UI: returns presigned URLs for every ML analysis output. The only public-facing
(Cognito-secured) service.

| | |
|---|---|
| **Type** | Zip Lambda (boto3 only — no ML deps) |
| **Trigger** | API Gateway `GET /files` with a Cognito User Pools authorizer |
| **Handler** | `app.lambda_handler` |
| **Memory / timeout** | 256 MB / 30 s |
| **Runtime deps** | none beyond the AWS runtime's boto3 |

## What it does
1. Defensively rejects unauthenticated requests (`401`) — API Gateway's authorizer is the
   primary gate; this is belt-and-braces (REQUIREMENTS UI-8).
2. Lists `analysis/*.json` in the output bucket and generates a presigned GET URL for each.
3. Returns `200` with the array, `404` if there are no analyses, `500` on error.

## Response (`200`)
```json
[
  { "filename": "analysis-d_2015_d_2019_le_2018_le_2022.json",
    "pre_signed_url": "https://…" }
]
```
CORS headers (`Access-Control-Allow-Origin: *`) are included on every response.

## Environment
| Var | Purpose | Default |
|-----|---------|---------|
| `OUTPUT_BUCKET` | bucket to list/sign | — |
| `ANALYSIS_PREFIX` | key prefix to list | `analysis/` |
| `URL_TTL_SECONDS` | presigned URL lifetime | `3600` |

IAM: read (list + get) on the output bucket.

## Notes
- The presigned URLs are unauthenticated once issued, so their short TTL is the access control
  on the analysis files; the UI fetches them directly (no auth header) after listing.
- Not exercised by `tools/test_all.py` (that path is offline); verify post-deploy by calling
  `GET /files` with a valid Cognito token and confirming the URLs resolve.
