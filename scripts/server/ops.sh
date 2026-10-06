#!/usr/bin/env bash
set -euo pipefail
APP_DIR="${APP_DIR:-/opt/domly-backend}"
ACTION="${1:-status}"
cd "$APP_DIR"
case "$ACTION" in
  status)
    echo "revision=$(cat REVISION 2>/dev/null || true)"
    docker compose ps
    curl -fsS http://127.0.0.1:8080/health || true
    echo
    curl -fsS http://127.0.0.1:8080/ready || true
    ;;
  logs)
    docker compose logs --tail=200 api worker | sed -E 's/(token|password|secret|key)=([^ ]+)/\1=***REDACTED***/gi'
    ;;
  restart)
    docker compose restart api worker
    ;;
  rollback)
    previous="$(ls -1dt releases/* 2>/dev/null | sed -n '2p')"
    test -n "$previous"
    ln -sfn "$previous" current
    rsync -a --delete --exclude 'backend/.env' --exclude 'backend/node_modules' --exclude 'backend/dist' current/ ./
    cp current/backend/.env backend/.env
    docker compose up -d --build api worker backup
    ;;
  *)
    echo "Unknown action" >&2
    exit 2
    ;;
esac
