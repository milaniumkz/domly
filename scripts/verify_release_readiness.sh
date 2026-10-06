#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-/Volumes/PD1000/job/flutter/bin/flutter}"
CUSTOMER_URL="${CUSTOMER_URL:-https://domly-d0f91.web.app}"
PRO_URL="${PRO_URL:-https://domly-pro.web.app}"
ADMIN_URL="${ADMIN_URL:-https://domly-admin-web.web.app}"

cd "$PROJECT_DIR"

source "$PROJECT_DIR/scripts/use_functions_node_env.sh"
echo "[1/11] check backend Node runtime"
"$PROJECT_DIR/scripts/check_functions_node_version.sh"

echo "[2/11] check Cloud Functions syntax"
node --check "$PROJECT_DIR/functions/index.js"

echo "[3/11] check Cloud Functions upload access"
"$PROJECT_DIR/scripts/check_functions_deploy_access.sh"

echo "[4/11] flutter analyze"
"$FLUTTER_BIN" analyze

echo "[5/11] flutter test"
"$FLUTTER_BIN" test

echo "[6/11] check release config consistency"
bash "$PROJECT_DIR/scripts/check_web_config_consistency.sh"

echo "[7/11] build customer web"
bash "$PROJECT_DIR/scripts/build_web_domly.sh"

echo "[8/11] build pro web"
bash "$PROJECT_DIR/scripts/build_web_domly_pro.sh"

echo "[9/11] build admin web"
bash "$PROJECT_DIR/scripts/build_web_admin.sh"

echo "[10/11] verify build titles"
grep -q "<title>DOMLY</title>" "$PROJECT_DIR/build/web-domly/index.html"
grep -q 'apple-mobile-web-app-title" content="DOMLY"' "$PROJECT_DIR/build/web-domly/index.html"
grep -q "<title>Domly Pro</title>" "$PROJECT_DIR/build/web-pro/index.html"
grep -q 'apple-mobile-web-app-title" content="Domly Pro"' "$PROJECT_DIR/build/web-pro/index.html"
grep -q "<title>Domly Admin Web</title>" "$PROJECT_DIR/build/web-admin/index.html"
grep -q 'apple-mobile-web-app-title" content="Domly Admin Web"' "$PROJECT_DIR/build/web-admin/index.html"
grep -q '"name": "DOMLY"' "$PROJECT_DIR/build/web-domly/manifest.json"
grep -q '"name": "Domly Pro"' "$PROJECT_DIR/build/web-pro/manifest.json"
grep -q '"name": "Domly Admin Web"' "$PROJECT_DIR/build/web-admin/manifest.json"

echo "[11/11] check production urls"
curl -fsSI "$CUSTOMER_URL" >/dev/null
curl -fsSI "$PRO_URL" >/dev/null
curl -fsSI "$ADMIN_URL" >/dev/null

echo "[OK] Release readiness checks passed"
