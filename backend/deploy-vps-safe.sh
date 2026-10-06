#!/usr/bin/env bash
set -euo pipefail

REMOTE="${REMOTE:-root@89.126.200.97}"
REMOTE_DIR="${REMOTE_DIR:-/opt/domly-backend}"
USE_CADDY="${USE_CADDY:-true}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rsync -az --delete \
  --exclude 'backend/.env' \
  --exclude 'backend/backups/' \
  --exclude 'backend/node_modules/' \
  --exclude 'backend/dist/' \
  --exclude '.dart_tool/' \
  --exclude 'build/' \
  "$ROOT_DIR/" "$REMOTE:$REMOTE_DIR/"

if [[ "$USE_CADDY" == "true" ]]; then
  ssh "$REMOTE" "cd '$REMOTE_DIR' && docker compose up -d --build api worker backup"
else
  ssh "$REMOTE" "cd '$REMOTE_DIR' && docker compose up -d --build api worker nginx backup"
fi

ssh "$REMOTE" "curl -fsS http://127.0.0.1:8080/ready >/dev/null && echo backend-ready"
