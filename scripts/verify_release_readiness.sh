#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
cd "$ROOT_DIR"
bash scripts/check_web_config_consistency.sh
(cd backend && npm test)
"$FLUTTER_BIN" analyze --no-fatal-infos --no-fatal-warnings
"$FLUTTER_BIN" test test/localization test/models test/services test/app
bash scripts/build_web_domly.sh
bash scripts/build_web_domly_pro.sh
bash scripts/build_web_admin.sh
