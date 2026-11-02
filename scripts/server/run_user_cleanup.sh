#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${APP_DIR:?}" "${CLEANUP_EXPECTED_PLAN:?}" "${CLEANUP_OPERATION_ID:?}"
[[ "$CLEANUP_EXPECTED_PLAN" =~ ^[a-f0-9]{64}$ ]]
[[ "$CLEANUP_OPERATION_ID" =~ ^[0-9]+$ ]]
exec 9>"$APP_DIR/shared/user-cleanup.lock"
flock -n 9
cd "$APP_DIR/current"
backup_dir="$APP_DIR/backups/user-cleanup/$CLEANUP_OPERATION_ID"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
compose() { docker compose -p domly-backend "$@"; }
restore_services() {
  result=$?
  trap - EXIT
  compose start api worker >/dev/null || result=1
  exit "$result"
}
trap restore_services EXIT
compose stop worker api
compose exec -T postgres sh -c 'exec pg_dump -Fc -U "${POSTGRES_USER:-domly}" "${POSTGRES_DB:-domly}"' > "$backup_dir/postgres.dump"
test -s "$backup_dir/postgres.dump"
compose exec -T postgres pg_restore --list < "$backup_dir/postgres.dump" > /dev/null
sha256sum "$backup_dir/postgres.dump" > "$backup_dir/postgres.dump.sha256"
# Keep a Redis snapshot before removing only jobs that reference deleted entities.
compose exec -T redis redis-cli --rdb /tmp/domly-user-cleanup.rdb > /dev/null
redis_container=$(compose ps -q redis)
docker cp "$redis_container:/tmp/domly-user-cleanup.rdb" "$backup_dir/redis.rdb" > /dev/null
compose exec -T redis rm /tmp/domly-user-cleanup.rdb
chmod 600 "$backup_dir/postgres.dump" "$backup_dir/redis.rdb" "$backup_dir/postgres.dump.sha256"
printf 'Verified private database and queue backups for operation %s\n' "$CLEANUP_OPERATION_ID"
compose run --rm --no-deps -T \
  -e CLEANUP_MODE=apply \
  -e CLEANUP_EXPECTED_PLAN="$CLEANUP_EXPECTED_PLAN" \
  -e CLEANUP_OPERATION_ID="$CLEANUP_OPERATION_ID" \
  -e CLEANUP_BACKUP_VERIFIED=true \
  -e CLEANUP_REDIS=true \
  api node < "$APP_DIR/shared/clear_non_admin_users.cjs" | tee "$backup_dir/result.json.log"
