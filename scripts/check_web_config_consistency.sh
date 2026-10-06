#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
for path in customer pro admin; do
  rg -q "location /$path/" backend/nginx/default.conf
done
rg -q '/customer/' scripts/build_web_domly.sh
rg -q '/pro/' scripts/build_web_domly_pro.sh
rg -q '/admin/' scripts/build_web_admin.sh
if rg -n 'firebase.*deploy|deploy.*hosting' scripts/deploy_all.sh scripts/deploy_web_all.sh; then exit 1; fi
echo 'Backend web hosting configuration is consistent.'
