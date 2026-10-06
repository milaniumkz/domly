#!/usr/bin/env bash
set -euo pipefail
APP_DIR="${APP_DIR:-/opt/domly-backend}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-domly-backend}"
umask 077
backup_path="$APP_DIR/backups/catalog-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_path"
postgres_container="$(docker ps -q --filter "label=com.docker.compose.project=$COMPOSE_PROJECT" --filter 'label=com.docker.compose.service=postgres')"
test -n "$postgres_container"
docker exec "$postgres_container" sh -c 'pg_dump -U "${POSTGRES_USER:-domly}" "${POSTGRES_DB:-domly}"' > "$backup_path/postgres.sql"
test -s "$backup_path/postgres.sql"
docker compose -p "$COMPOSE_PROJECT" -f "$APP_DIR/current/docker-compose.yml" --project-directory "$APP_DIR/current" exec -T api node dist/scripts/import-firestore-catalog.js
