#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/domly-backend}"
RELEASES_DIR="$APP_DIR/releases"
BACKUP_DIR="$APP_DIR/backups"
CURRENT_DIR="$APP_DIR/current"
SHARED_DIR="$APP_DIR/shared"
SHARED_ENV="$SHARED_DIR/backend.env"
COMMIT_SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
RELEASE_DIR="$RELEASES_DIR/$COMMIT_SHA"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8080/health}"
READY_URL="${READY_URL:-http://127.0.0.1:8080/ready}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-domly-backend}"

mkdir -p "$RELEASES_DIR" "$BACKUP_DIR" "$SHARED_DIR"

if [ -f "$SHARED_ENV" ]; then
  mkdir -p "$RELEASE_DIR/backend"
  cp "$SHARED_ENV" "$RELEASE_DIR/backend/.env"
elif [ -f "$APP_DIR/backend/.env" ]; then
  mkdir -p "$RELEASE_DIR/backend"
  cp "$APP_DIR/backend/.env" "$RELEASE_DIR/backend/.env"
elif [ -f "$CURRENT_DIR/backend/.env" ]; then
  mkdir -p "$RELEASE_DIR/backend"
  cp "$CURRENT_DIR/backend/.env" "$RELEASE_DIR/backend/.env"
else
  echo "Missing production backend/.env on server" >&2
  exit 1
fi
cp "$RELEASE_DIR/backend/.env" "$SHARED_ENV"

backup_stamp="$(date +%Y%m%d-%H%M%S)-$COMMIT_SHA"
mkdir -p "$BACKUP_DIR/$backup_stamp"
cp "$RELEASE_DIR/backend/.env" "$BACKUP_DIR/$backup_stamp/backend.env"

postgres_container="$(docker ps -q --filter "label=com.docker.compose.project=$COMPOSE_PROJECT" --filter 'label=com.docker.compose.service=postgres')"
if [ -n "$postgres_container" ]; then
  docker exec "$postgres_container" sh -c 'pg_dump -U "${POSTGRES_USER:-domly}" "${POSTGRES_DB:-domly}"' > "$BACKUP_DIR/$backup_stamp/postgres.sql"
fi

if [ -n "${OTP_SHOW_CODE:-}" ]; then
  RELEASE_ENV="$RELEASE_DIR/backend/.env" python3 - <<'PYCODE'
import os, pathlib
value = os.environ['OTP_SHOW_CODE'].lower()
if value not in ('true', 'false'):
    raise SystemExit('OTP_SHOW_CODE must be true or false')
p = pathlib.Path(os.environ['RELEASE_ENV'])
lines = [line for line in p.read_text().splitlines() if not line.startswith(('OTP_SHOW_CODE=', 'OTP_FAILURE_FALLBACK_UNTIL='))]
p.write_text('\n'.join(lines) + '\nOTP_SHOW_CODE=' + value + '\n')
p.chmod(0o600)
PYCODE
  cp "$RELEASE_DIR/backend/.env" "$SHARED_ENV"
fi

if [ -n "${PUBLIC_API_URL:-}" ]; then
  RELEASE_ENV="$RELEASE_DIR/backend/.env" python3 - <<'PYCODE'
import os, pathlib, urllib.parse
value = os.environ['PUBLIC_API_URL'].rstrip('/')
url = urllib.parse.urlparse(value)
if url.scheme != 'https' or not url.netloc or url.path or url.query or url.fragment or url.username:
    raise SystemExit('PUBLIC_API_URL must be a public HTTPS origin')
p = pathlib.Path(os.environ['RELEASE_ENV'])
lines = [line for line in p.read_text().splitlines() if not line.startswith('PUBLIC_API_URL=')]
p.write_text('\n'.join(lines) + '\nPUBLIC_API_URL=' + value + '\n')
p.chmod(0o600)
PYCODE
  cp "$RELEASE_DIR/backend/.env" "$SHARED_ENV"
fi

ln -sfn "$RELEASE_DIR" "$CURRENT_DIR"
echo "$COMMIT_SHA" > "$APP_DIR/REVISION"

docker compose -p "$COMPOSE_PROJECT" -f "$CURRENT_DIR/docker-compose.yml" --project-directory "$CURRENT_DIR" up -d --build api worker backup

for i in {1..30}; do
  if curl -fsS "$HEALTH_URL" >/dev/null && curl -fsS "$READY_URL" >/dev/null; then
    schema_ready="$(docker compose -p "$COMPOSE_PROJECT" -f "$CURRENT_DIR/docker-compose.yml" --project-directory "$CURRENT_DIR" exec -T postgres sh -c 'exec psql -U "${POSTGRES_USER:-domly}" -d "${POSTGRES_DB:-domly}" -v ON_ERROR_STOP=1 -At' <<'SQL'
SELECT count(*) FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'quality_check_requests'
AND column_name = 'admin_comment';
SQL
)"
    if [ "$schema_ready" != "1" ]; then
      echo "Deploy failed: quality_check_requests.admin_comment is missing" >&2
      exit 1
    fi
    docker compose -p "$COMPOSE_PROJECT" -f "$CURRENT_DIR/docker-compose.yml" --project-directory "$CURRENT_DIR" exec -T api node dist/scripts/repair-area-bonuses.js
    if systemctl is-active --quiet caddy; then
      chmod -R a+rX "$CURRENT_DIR/frontend/releases/current"
      APP_DIR="$APP_DIR" GITHUB_SHA="$COMMIT_SHA" python3 "$CURRENT_DIR/scripts/server/publish_web_caddy.py"
    else
      docker compose -p "$COMPOSE_PROJECT" -f "$CURRENT_DIR/docker-compose.yml" --project-directory "$CURRENT_DIR" up -d nginx
    fi
    docker compose -p "$COMPOSE_PROJECT" -f "$CURRENT_DIR/docker-compose.yml" --project-directory "$CURRENT_DIR" exec -T api node -e "console.log('OTP code display:', process.env.OTP_SHOW_CODE === 'true' ? 'enabled until explicitly disabled' : 'disabled')"
    echo "Deploy OK: $COMMIT_SHA"
    exit 0
  fi
  sleep 5
done

echo "Deploy failed healthcheck" >&2
docker compose -p "$COMPOSE_PROJECT" -f "$CURRENT_DIR/docker-compose.yml" --project-directory "$CURRENT_DIR" ps >&2 || true
exit 1
