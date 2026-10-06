#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/use_functions_node_env.sh"
"$ROOT_DIR/scripts/check_functions_node_version.sh"
"$ROOT_DIR/scripts/check_functions_deploy_access.sh"

if [[ ! -f "functions/.env" ]]; then
  if [[ -f "functions/.env.example" ]]; then
    cp functions/.env.example functions/.env
    echo "[INFO] Created functions/.env from template. Fill in production values before deploy."
  else
    echo "[ERROR] functions/.env and functions/.env.example are missing"
    exit 1
  fi
fi

echo "[INFO] Checking Cloud Functions syntax"
node --check functions/index.js

"$ROOT_DIR/scripts/install_functions_dependencies.sh"

echo "[INFO] Backend is prepared. Next step:"
echo "./scripts/deploy_all.sh        # rules, indexes, storage, functions"
echo "./scripts/deploy_functions.sh  # signInWithOtp only"
echo "./scripts/deploy_web_all.sh   # deploy customer, pro, and admin hosting separately"
