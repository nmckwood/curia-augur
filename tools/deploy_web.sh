#!/usr/bin/env bash
# Build the Flutter web app and sync it (plus the GeoJSON boundaries) to the web
# bucket, then invalidate CloudFront. Mirrors the hof reference CI flow.
#
# Usage:
#   WEB_BUCKET=curia-augur-web-<acct> \
#   API_BASE_URL=https://api.curia-augur.<your-domain> \
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

if [ -n "${DISTRIBUTION_ID:-}" ]; then
  aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths "/*"
fi
echo "web deploy complete"
