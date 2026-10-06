#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FUNCTIONS_PACKAGE_JSON="$ROOT_DIR/functions/package.json"

if [[ "${FUNCTIONS_NODE_ENV_READY:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

if [[ ! -f "$FUNCTIONS_PACKAGE_JSON" ]]; then
  echo "[ERROR] functions/package.json is missing" >&2
  return 1 2>/dev/null || exit 1
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

candidate_bins=(
  "/opt/homebrew/opt/node@${required_major}/bin"
  "/usr/local/opt/node@${required_major}/bin"
)

for bin_dir in "${candidate_bins[@]}"; do
  if [[ -x "$bin_dir/node" ]]; then
    export PATH="$bin_dir:$PATH"
    export FUNCTIONS_NODE_BIN_DIR="$bin_dir"
    export FUNCTIONS_NODE_MAJOR="$required_major"
    export FUNCTIONS_NODE_VERSION="$("$bin_dir/node" -v)"
    export FUNCTIONS_NODE_AUTOSELECTED="1"
    export FUNCTIONS_NODE_ENV_READY="1"
    echo "[INFO] Using Node runtime from $bin_dir (${FUNCTIONS_NODE_VERSION})"
    return 0 2>/dev/null || exit 0
  fi
done

current_major=""
current_version=""
if command -v node >/dev/null 2>&1; then
  current_major="$(node -p "process.versions.node.split('.')[0]")"
  current_version="$(node -v)"
fi

if [[ -n "$current_major" && "$current_major" == "$required_major" ]]; then
  export FUNCTIONS_NODE_BIN_DIR="$(dirname "$(command -v node)")"
  export FUNCTIONS_NODE_MAJOR="$current_major"
  export FUNCTIONS_NODE_VERSION="$current_version"
  export FUNCTIONS_NODE_AUTOSELECTED="0"
  export FUNCTIONS_NODE_ENV_READY="1"
  return 0 2>/dev/null || exit 0
fi

export FUNCTIONS_NODE_ENV_READY="1"
return 0 2>/dev/null || exit 0
