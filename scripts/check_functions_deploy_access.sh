#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ID="${PROJECT_ID:-domly-d0f91}"
LOCATION="${LOCATION:-us-central1}"

source "$ROOT_DIR/scripts/use_functions_node_env.sh"
"$ROOT_DIR/scripts/check_functions_node_version.sh" >/dev/null

if ! command -v gcloud >/dev/null 2>&1; then
  echo "[ERROR] gcloud is not installed"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "[ERROR] curl is not installed"
  exit 2
fi

if ! firebase login:list >/dev/null 2>&1; then
  echo "[ERROR] Firebase auth required. Run: firebase login --reauth"
  exit 3
fi
firebase_user="$(firebase login:list 2>/dev/null | tail -n 1 | sed 's/^.*as //')"

app_engine_location="$(gcloud app describe --project "$PROJECT_ID" --format='value(locationId)' 2>/dev/null || true)"
if [[ -z "$app_engine_location" ]]; then
  echo "[ERROR] App Engine is not initialized for project $PROJECT_ID"
  exit 4
fi

billing_enabled="$(gcloud beta billing projects describe "$PROJECT_ID" --format='value(billingEnabled)' 2>/dev/null || true)"
if [[ "$billing_enabled" != "True" && "$billing_enabled" != "true" ]]; then
  echo "[ERROR] Billing is not enabled for project $PROJECT_ID"
  exit 5
fi

token="$(gcloud auth print-access-token 2>/dev/null || true)"
if [[ -z "$token" ]]; then
  echo "[ERROR] Could not obtain gcloud access token"
  exit 6
fi

tmp_body="$(mktemp)"
tmp_status="$(mktemp)"
trap 'rm -f "$tmp_body" "$tmp_status"' EXIT

http_code="$(
  curl -sS \
    -o "$tmp_body" \
    -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "https://cloudfunctions.googleapis.com/v2/projects/${PROJECT_ID}/locations/${LOCATION}/functions:generateUploadUrl" \
    -d '{}' || true
)"

printf '%s' "$http_code" > "$tmp_status"

if [[ "$http_code" == "200" ]]; then
  echo "[OK] Functions upload access probe passed for ${PROJECT_ID}/${LOCATION}"
  echo "[INFO] App Engine location: $app_engine_location"
  echo "[INFO] Billing enabled: $billing_enabled"
  exit 0
fi

echo "[ERROR] Functions upload access probe failed for ${PROJECT_ID}/${LOCATION} (HTTP ${http_code})"
echo "[INFO] App Engine location: $app_engine_location"
echo "[INFO] Billing enabled: $billing_enabled"
echo "[INFO] Firebase user: ${firebase_user}"
echo "[INFO] Response body:"
cat "$tmp_body"
exit 7
