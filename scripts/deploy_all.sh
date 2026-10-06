#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FUNCTIONS_DIR="$ROOT_DIR/functions"
PROJECT_ID="${PROJECT_ID:-domly-d0f91}"
FIREBASE_BIN="${FIREBASE_BIN:-firebase}"

cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/use_functions_node_env.sh"
"$ROOT_DIR/scripts/check_functions_node_version.sh"
"$ROOT_DIR/scripts/check_functions_deploy_access.sh"

if ! "$FIREBASE_BIN" login:list >/dev/null 2>&1; then
  echo "[ERROR] Firebase auth required. Run: firebase login --reauth"
  exit 1
fi

if [[ ! -f "$FUNCTIONS_DIR/.env" ]]; then
  echo "[ERROR] functions/.env is missing. Create it from functions/.env.example and fill production values."
  exit 2
fi

required_vars=(
  EPAY_INVOICE_CLIENT_ID
  EPAY_INVOICE_CLIENT_SECRET
  EPAY_PAYOUT_CLIENT_ID
  EPAY_PAYOUT_CLIENT_SECRET
  EPAY_SHOP_ID
  EPAY_TERMINAL_ID
  EPAY_PAYOUT_TERMINAL_ID
)

set -a
source "$FUNCTIONS_DIR/.env"
set +a

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "[ERROR] Missing required variable in functions/.env: ${var_name}"
    exit 3
  fi
done

"$FIREBASE_BIN" use "$PROJECT_ID"
"$FIREBASE_BIN" deploy --only firestore:rules,firestore:indexes,storage

"$ROOT_DIR/scripts/install_functions_dependencies.sh"

"$FIREBASE_BIN" deploy --only functions

echo "[INFO] Backend deployed. Web hosting must be deployed separately:"
echo "       ./scripts/deploy_web_all.sh"

echo "[OK] Backend deploy finished"
