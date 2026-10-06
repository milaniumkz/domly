#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FUNCTIONS_DIR="$ROOT_DIR/functions"

source "$ROOT_DIR/scripts/use_functions_node_env.sh"
"$ROOT_DIR/scripts/check_functions_node_version.sh" >/dev/null

if [[ ! -d "$FUNCTIONS_DIR" ]]; then
  echo "[ERROR] functions directory is missing"
  exit 1
fi

cd "$FUNCTIONS_DIR"

if [[ -f "package-lock.json" ]]; then
  echo "[INFO] Installing functions dependencies with npm ci"
  npm ci
else
  echo "[INFO] package-lock.json is missing, falling back to npm install"
  npm install
fi
