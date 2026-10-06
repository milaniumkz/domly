#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
if [[ "$(git branch --show-current)" != main ]]; then
  echo "Production deploy requires main." >&2
  exit 1
fi
"$ROOT_DIR/scripts/prepare_backend_deploy.sh"
gh workflow run deploy.yml --repo milaniumkz/domly --ref main
