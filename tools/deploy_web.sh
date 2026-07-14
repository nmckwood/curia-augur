#!/usr/bin/env bash
# Build the Flutter web app and sync it (plus the GeoJSON boundaries) to the web
# bucket, then invalidate CloudFront. Mirrors the hof reference CI flow.
#
# Usage:
#   WEB_BUCKET=curia-augur-web-<acct> \
#   API_BASE_URL=https://api.curia-augur.howfhowfhowf.com \
#   COGNITO_USER_POOL_ID=... COGNITO_CLIENT_ID=... \
#   DISTRIBUTION_ID=... \
#   tools/deploy_web.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI="$ROOT/frontend/curia_augur_ui"
GEO="$ROOT/data/geospatial_data"

: "${WEB_BUCKET:?set WEB_BUCKET}"
: "${API_BASE_URL:?set API_BASE_URL}"
: "${COGNITO_USER_POOL_ID:?set COGNITO_USER_POOL_ID}"
: "${COGNITO_CLIENT_ID:?set COGNITO_CLIENT_ID}"

cd "$UI"
flutter build web \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=COGNITO_USER_POOL_ID="$COGNITO_USER_POOL_ID" \
  --dart-define=COGNITO_CLIENT_ID="$COGNITO_CLIENT_ID"

aws s3 sync build/web/ "s3://$WEB_BUCKET" --delete

# Publish simplified GeoJSON boundaries under /geo with the names the UI expects
# (REQ UI-4). The raw BFC files are ~200 MB, so they are simplified first (~2-3 MB).
PY="${PYTHON:-python3}"
"$PY" "$ROOT/tools/simplify_geojson.py" \
  --input "$GEO/Local_Authority_Districts_December_2022_UK_BFC_V2_-4534861255799681503.geojson" \
  --output /tmp/boundaries_2022.geojson
"$PY" "$ROOT/tools/simplify_geojson.py" \
  --input "$GEO/Local_Authority_Districts_DEC_2025_Boundaries_UK_BFC_5780731924739583250.geojson" \
  --output /tmp/boundaries_2025.geojson
aws s3 cp /tmp/boundaries_2022.geojson "s3://$WEB_BUCKET/geo/boundaries_2022.geojson" \
  --content-type application/geo+json
aws s3 cp /tmp/boundaries_2025.geojson "s3://$WEB_BUCKET/geo/boundaries_2025.geojson" \
  --content-type application/geo+json

if [ -n "${DISTRIBUTION_ID:-}" ]; then
  aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths "/*"
fi
echo "web deploy complete"
