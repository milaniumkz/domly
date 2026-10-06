#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FUNCTIONS_PACKAGE_JSON="$ROOT_DIR/functions/package.json"

source "$ROOT_DIR/scripts/use_functions_node_env.sh"

if [[ ! -f "$FUNCTIONS_PACKAGE_JSON" ]]; then
  echo "[ERROR] functions/package.json is missing"
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "[ERROR] Node.js is not installed"
  exit 2
fi

required_major="$(python3 - <<'PY' "$FUNCTIONS_PACKAGE_JSON"
import json, re, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
raw = str(((data.get('engines') or {}).get('node')) or '')
m = re.search(r'(\d+)', raw)
if not m:
    raise SystemExit(1)
print(m.group(1))
PY
)"
current_major="$(node -p "process.versions.node.split('.')[0]")"
current_version="$(node -v)"

if [[ "$current_major" != "$required_major" ]]; then
  echo "[ERROR] functions require Node.js ${required_major}.x, current runtime is ${current_version}"
  echo "[INFO] Switch Node before running functions install/deploy scripts."
  echo "[INFO] If you use Homebrew: brew install node@${required_major}"
  echo "[INFO] Then make it available in PATH or let scripts auto-detect /opt/homebrew/opt/node@${required_major}/bin/node"
  exit 3
fi

echo "[OK] Node runtime matches functions requirement: ${current_version}"
