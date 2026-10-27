#!/usr/bin/env bash
set -euo pipefail
app_root=$1
reset_mode=$2
operation_id=$3
expected_plan=${4:-}
[[ "$reset_mode" =~ ^(audit|rehearse|apply)$ ]]
[[ "$operation_id" =~ ^[0-9]+$ ]]
[[ -z "$expected_plan" || "$expected_plan" =~ ^[a-f0-9]{64}$ ]]
cd "$app_root/current"
umask 077
backup_dir="$app_root/backups/user-reset/$operation_id"
mkdir -p "$backup_dir"
compose=(docker compose -p domly-backend)
if [ "$reset_mode" = apply ]; then
  test -n "$expected_plan"
  # Avoid new registrations, callbacks and background work between backup and reset.
  "${compose[@]}" stop -t 60 api worker
  trap '"${compose[@]}" start api worker >/dev/null' EXIT
  "${compose[@]}" exec -T postgres sh -c 'pg_dump -Fc -U "${POSTGRES_USER:-domly}" "${POSTGRES_DB:-domly}"' > "$backup_dir/database.dump"
  test -s "$backup_dir/database.dump"
  "${compose[@]}" exec -T postgres pg_restore --list < "$backup_dir/database.dump" > "$backup_dir/database.contents"
  test -s "$backup_dir/database.contents"
  cp backend/.env "$backup_dir/backend.env"
  sha256sum "$backup_dir/database.dump" > "$backup_dir/database.sha256"
  echo 'Verified database backup created'
fi
"${compose[@]}" run -T --rm --no-deps --entrypoint node \
  -e RESET_MODE="$reset_mode" -e RESET_EXPECTED_PLAN="$expected_plan" \
  -e RESET_OPERATION_ID="$operation_id" api \
  < "$app_root/shared/reset_test_users.cjs" > "$backup_dir/report.json"
cat "$backup_dir/report.json"
if [ "$reset_mode" = apply ]; then
  "${compose[@]}" start api worker >/dev/null
  trap - EXIT
  for attempt in $(seq 1 30); do
    if curl -fsS http://localhost:8080/ready >/dev/null; then echo 'Ready after reset'; exit 0; fi
    sleep 2
  done
  exit 1
fi
