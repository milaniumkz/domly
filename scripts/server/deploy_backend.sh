#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/domly-backend}"
RELEASES_DIR="$APP_DIR/releases"
BACKUP_DIR="$APP_DIR/backups"
CURRENT_DIR="$APP_DIR/current"
COMMIT_SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
RELEASE_DIR="$RELEASES_DIR/$COMMIT_SHA"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8080/health}"
READY_URL="${READY_URL:-http://127.0.0.1:8080/ready}"

mkdir -p "$RELEASES_DIR" "$BACKUP_DIR"

if [ -f "$APP_DIR/backend/.env" ]; then
  mkdir -p "$RELEASE_DIR/backend"
  cp "$APP_DIR/backend/.env" "$RELEASE_DIR/backend/.env"
elif [ -f "$CURRENT_DIR/backend/.env" ]; then
  mkdir -p "$RELEASE_DIR/backend"
  cp "$CURRENT_DIR/backend/.env" "$RELEASE_DIR/backend/.env"
else
  echo "Missing production backend/.env on server" >&2
  exit 1
fi

backup_stamp="$(date +%Y%m%d-%H%M%S)-$COMMIT_SHA"
mkdir -p "$BACKUP_DIR/$backup_stamp"
cp "$RELEASE_DIR/backend/.env" "$BACKUP_DIR/$backup_stamp/backend.env"

if docker compose -f "$APP_DIR/docker-compose.yml" ps postgres >/dev/null 2>&1; then
  docker compose -f "$APP_DIR/docker-compose.yml" exec -T postgres pg_dump -U "${POSTGRES_USER:-domly}" "${POSTGRES_DB:-domly}" > "$BACKUP_DIR/$backup_stamp/postgres.sql" || true
fi

ln -sfn "$RELEASE_DIR" "$CURRENT_DIR"
rsync -a --delete --exclude 'backend/.env' --exclude 'backend/node_modules' --exclude 'backend/dist' "$CURRENT_DIR/" "$APP_DIR/"
cp "$RELEASE_DIR/backend/.env" "$APP_DIR/backend/.env"

echo "$COMMIT_SHA" > "$APP_DIR/REVISION"

docker compose -f "$APP_DIR/docker-compose.yml" up -d --build api worker backup

for i in {1..30}; do
  if curl -fsS "$HEALTH_URL" >/dev/null && curl -fsS "$READY_URL" >/dev/null; then
    echo "Deploy OK: $COMMIT_SHA"
    exit 0
  fi
  sleep 5
done

echo "Deploy failed healthcheck" >&2
docker compose -f "$APP_DIR/docker-compose.yml" ps >&2 || true
exit 1
