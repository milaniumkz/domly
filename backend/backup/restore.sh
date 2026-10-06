#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups}"
MINIO_RESTORE_ENABLED="${MINIO_RESTORE_ENABLED:-true}"
RESTORE_CONFIRM="${RESTORE_CONFIRM:-}"

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required env: ${name}" >&2
    exit 1
  fi
}

latest_file() {
  local pattern="$1"
  find "${BACKUP_DIR}" -type f -name "${pattern}" -print | sort | tail -n 1
}

verify_sha_if_present() {
  local file="$1"
  local sha="$2"
  if [ -z "${sha}" ]; then
    return 0
  fi
  echo "${sha}  ${file}" | sha256sum -c -
}

if [ "${RESTORE_CONFIRM}" != "YES" ]; then
  echo "Refusing restore. Set RESTORE_CONFIRM=YES to continue." >&2
  exit 1
fi

require_env DATABASE_URL

POSTGRES_BACKUP="${POSTGRES_BACKUP:-$(latest_file 'domly_*.sql.gz')}"
if [ -z "${POSTGRES_BACKUP}" ] || [ ! -f "${POSTGRES_BACKUP}" ]; then
  echo "PostgreSQL backup not found. Set POSTGRES_BACKUP=/backups/postgres/domly_....sql.gz" >&2
  exit 1
fi

echo "Restoring PostgreSQL from ${POSTGRES_BACKUP}..."
if [ -n "${POSTGRES_BACKUP_SHA256:-}" ]; then
  verify_sha_if_present "${POSTGRES_BACKUP}" "${POSTGRES_BACKUP_SHA256}"
fi
gunzip -c "${POSTGRES_BACKUP}" | psql "${DATABASE_URL}" -v ON_ERROR_STOP=1

if [ "${MINIO_RESTORE_ENABLED}" = "true" ]; then
  require_env BACKUP_S3_ENDPOINT
  require_env MINIO_ACCESS_KEY
  require_env MINIO_SECRET_KEY
  require_env MINIO_BUCKET

  MINIO_BACKUP="${MINIO_BACKUP:-$(latest_file 'domly_minio_*.tar.gz')}"
  if [ -z "${MINIO_BACKUP}" ] || [ ! -f "${MINIO_BACKUP}" ]; then
    echo "MinIO backup not found. Set MINIO_BACKUP=/backups/minio/domly_minio_....tar.gz or MINIO_RESTORE_ENABLED=false" >&2
    exit 1
  fi

  echo "Restoring MinIO from ${MINIO_BACKUP}..."
  if [ -n "${MINIO_BACKUP_SHA256:-}" ]; then
    verify_sha_if_present "${MINIO_BACKUP}" "${MINIO_BACKUP_SHA256}"
  fi
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT
  tar -C "${tmp_dir}" -xzf "${MINIO_BACKUP}"
  mc alias set domly-minio "${BACKUP_S3_ENDPOINT}" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}" >/dev/null
  mc mb --ignore-existing "domly-minio/${MINIO_BUCKET}" >/dev/null
  mc mirror --overwrite "${tmp_dir}" "domly-minio/${MINIO_BUCKET}" >/dev/null
fi

echo "Restore finished."
