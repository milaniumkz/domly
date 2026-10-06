#!/bin/sh
set -eu

if [ -n "${DATABASE_URL:-}" ]; then
  echo "Waiting for PostgreSQL..."
  until psql "$DATABASE_URL" -c "SELECT 1" >/dev/null 2>&1; do
    sleep 2
  done
  echo "Applying schema with migration lock..."
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
SELECT pg_advisory_lock(76197001);
\i /app/sql/schema.sql
SELECT pg_advisory_unlock(76197001);
SQL
fi

exec "$@"
