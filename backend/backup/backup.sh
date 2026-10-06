#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
BACKUP_INTERVAL_SECONDS="${BACKUP_INTERVAL_SECONDS:-86400}"
MINIO_BACKUP_ENABLED="${MINIO_BACKUP_ENABLED:-true}"
BACKUP_MANIFEST="${BACKUP_MANIFEST:-${BACKUP_DIR}/manifest.jsonl}"

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required env: ${name}" >&2
    exit 1
  fi
}

run_backup() {
  require_env DATABASE_URL

  local stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "${BACKUP_DIR}/postgres" "${BACKUP_DIR}/minio"
  mkdir -p "$(dirname "${BACKUP_MANIFEST}")"

  echo "Creating PostgreSQL backup ${stamp}..."
  pg_dump "${DATABASE_URL}" | gzip > "${BACKUP_DIR}/postgres/domly_${stamp}.sql.gz.tmp"
  mv "${BACKUP_DIR}/postgres/domly_${stamp}.sql.gz.tmp" "${BACKUP_DIR}/postgres/domly_${stamp}.sql.gz"
  local postgres_file postgres_sha postgres_size
  postgres_file="${BACKUP_DIR}/postgres/domly_${stamp}.sql.gz"
  postgres_sha="$(sha256sum "${postgres_file}" | awk '{print $1}')"
  postgres_size="$(wc -c < "${postgres_file}" | tr -d ' ')"

  if [ "${MINIO_BACKUP_ENABLED}" = "true" ]; then
    require_env BACKUP_S3_ENDPOINT
    require_env MINIO_ACCESS_KEY
    require_env MINIO_SECRET_KEY
    require_env MINIO_BUCKET

    echo "Creating MinIO backup ${stamp}..."
    mc alias set domly-minio "${BACKUP_S3_ENDPOINT}" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}" >/dev/null
    mc mb --ignore-existing "domly-minio/${MINIO_BUCKET}" >/dev/null
    rm -rf "${BACKUP_DIR}/minio/latest"
    mkdir -p "${BACKUP_DIR}/minio/latest"
    mc mirror --overwrite "domly-minio/${MINIO_BUCKET}" "${BACKUP_DIR}/minio/latest" >/dev/null
    tar -C "${BACKUP_DIR}/minio/latest" -czf "${BACKUP_DIR}/minio/domly_minio_${stamp}.tar.gz.tmp" .
    mv "${BACKUP_DIR}/minio/domly_minio_${stamp}.tar.gz.tmp" "${BACKUP_DIR}/minio/domly_minio_${stamp}.tar.gz"
  fi

  local minio_file="" minio_sha="" minio_size=0
  if [ -f "${BACKUP_DIR}/minio/domly_minio_${stamp}.tar.gz" ]; then
    minio_file="${BACKUP_DIR}/minio/domly_minio_${stamp}.tar.gz"
    minio_sha="$(sha256sum "${minio_file}" | awk '{print $1}')"
    minio_size="$(wc -c < "${minio_file}" | tr -d ' ')"
  fi

  printf '{"createdAt":"%s","postgres":{"path":"%s","sha256":"%s","bytes":%s},"minio":{"enabled":%s,"path":"%s","sha256":"%s","bytes":%s}}\n' \
    "${stamp}" \
    "${postgres_file}" \
    "${postgres_sha}" \
    "${postgres_size}" \
    "${MINIO_BACKUP_ENABLED}" \
    "${minio_file}" \
    "${minio_sha}" \
    "${minio_size}" >> "${BACKUP_MANIFEST}"
  cp "${BACKUP_MANIFEST}" "${BACKUP_DIR}/manifest.latest.jsonl"

  find "${BACKUP_DIR}/postgres" -type f -name 'domly_*.sql.gz' -mtime +"${BACKUP_KEEP_DAYS}" -delete
  find "${BACKUP_DIR}/minio" -type f -name 'domly_minio_*.tar.gz' -mtime +"${BACKUP_KEEP_DAYS}" -delete
  echo "Backup finished ${stamp}."
}

if [ "${BACKUP_ONCE:-false}" = "true" ]; then
  run_backup
  exit 0
fi

while true; do
  run_backup
  sleep "${BACKUP_INTERVAL_SECONDS}"
done
