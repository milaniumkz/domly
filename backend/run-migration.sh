#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

EXPORT_DIR="${FIREBASE_EXPORT_DIR:-$ROOT_DIR/firebase-export}"
REPORT_DIR="${MIGRATION_REPORT_DIR:-$EXPORT_DIR}"

if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  echo "ERROR: set GOOGLE_APPLICATION_CREDENTIALS=/secure/firebase-service-account.json" >&2
  exit 1
fi

if [[ ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
  echo "ERROR: GOOGLE_APPLICATION_CREDENTIALS file not found: $GOOGLE_APPLICATION_CREDENTIALS" >&2
  exit 1
fi

mkdir -p "$EXPORT_DIR" "$REPORT_DIR"

echo "1/4 Export Firestore/Storage metadata to $EXPORT_DIR"
FIREBASE_EXPORT_DIR="$EXPORT_DIR" npm run firebase:export

echo "2/4 Audit export"
FIREBASE_EXPORT_DIR="$EXPORT_DIR" \
MIGRATION_AUDIT_OUT="$REPORT_DIR/migration-audit.json" \
npm run firebase:audit

echo "3/4 Import to PostgreSQL"
FIREBASE_EXPORT_DIR="$EXPORT_DIR" npm run firebase:import

echo "4/4 Verify migration"
FIREBASE_EXPORT_DIR="$EXPORT_DIR" \
MIGRATION_VERIFY_OUT="$REPORT_DIR/migration-verify.json" \
npm run firebase:verify

echo "Done."
echo "Audit:  $REPORT_DIR/migration-audit.json"
echo "Verify: $REPORT_DIR/migration-verify.json"
