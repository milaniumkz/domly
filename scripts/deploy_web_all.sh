#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ID="${PROJECT_ID:-domly-d0f91}"
FIREBASE_BIN="${FIREBASE_BIN:-firebase}"

"$PROJECT_DIR/scripts/build_web_domly.sh"
"$PROJECT_DIR/scripts/build_web_domly_pro.sh"
"$PROJECT_DIR/scripts/build_web_admin.sh"

grep -q "<title>DOMLY</title>" "$PROJECT_DIR/build/web-domly/index.html"
grep -q 'apple-mobile-web-app-title" content="DOMLY"' "$PROJECT_DIR/build/web-domly/index.html"
grep -q "<title>Domly Pro</title>" "$PROJECT_DIR/build/web-pro/index.html"
grep -q 'apple-mobile-web-app-title" content="Domly Pro"' "$PROJECT_DIR/build/web-pro/index.html"
grep -q "<title>Domly Admin Web</title>" "$PROJECT_DIR/build/web-admin/index.html"
grep -q 'apple-mobile-web-app-title" content="Domly Admin Web"' "$PROJECT_DIR/build/web-admin/index.html"

"$FIREBASE_BIN" deploy \
  --only hosting:domly-d0f91,hosting:domly-pro \
  --project "$PROJECT_ID" \
  --config "$PROJECT_DIR/firebase.hosting.multi.json"

"$FIREBASE_BIN" deploy \
  --only hosting:domly-admin-web \
  --project "$PROJECT_ID" \
  --config "$PROJECT_DIR/firebase.hosting.admin.json"

"$PROJECT_DIR/scripts/post_deploy_web_smoke.sh"

echo "✓ Deployed customer, pro, and admin hosting"
