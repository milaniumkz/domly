#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FUNCTIONS_DIR="$ROOT_DIR/functions"
PROJECT_ID="${PROJECT_ID:-domly-d0f91}"
FIREBASE_BIN="${FIREBASE_BIN:-firebase}"
FUNCTIONS_TARGET="${FUNCTIONS_TARGET:-signInWithOtp}"

source "$ROOT_DIR/scripts/use_functions_node_env.sh"
"$ROOT_DIR/scripts/check_functions_node_version.sh"
"$ROOT_DIR/scripts/check_functions_deploy_access.sh"

cd "$ROOT_DIR"

if ! "$FIREBASE_BIN" login:list >/dev/null 2>&1; then
  echo "[ERROR] Firebase auth required. Run: firebase login --reauth"
  exit 1
fi

if [[ ! -f "$FUNCTIONS_DIR/.env" ]]; then
  echo "[ERROR] functions/.env is missing. Create it from functions/.env.example and fill required values."
  exit 2
fi

echo "[INFO] Checking Cloud Functions syntax"
node --check "$FUNCTIONS_DIR/index.js"

"$ROOT_DIR/scripts/install_functions_dependencies.sh"

# Deploy only the signInWithOtp function (required for WhatsApp OTP auth)
export FUNCTIONS_DISCOVERY_TIMEOUT="${FUNCTIONS_DISCOVERY_TIMEOUT:-60}"

"$FIREBASE_BIN" use "$PROJECT_ID"
"$FIREBASE_BIN" deploy --only "functions:${FUNCTIONS_TARGET}" --project "$PROJECT_ID"
