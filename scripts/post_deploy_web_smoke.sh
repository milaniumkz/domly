#!/usr/bin/env bash
set -euo pipefail

CUSTOMER_URL="${CUSTOMER_URL:-https://domly.kz/customer/}"
PRO_URL="${PRO_URL:-https://domly.kz/pro/}"
ADMIN_URL="${ADMIN_URL:-https://domly.kz/admin/}"

check_url() {
  local label="$1"
  local url="$2"
  local expected_title="$3"
  local tmp
  tmp="$(mktemp)"

  echo "[CHECK] $label -> $url"
  curl -fsSL "$url" -o "$tmp"

  if grep -q "Site Not Found" "$tmp"; then
    echo "[ERROR] $label returns Site Not Found"
    rm -f "$tmp"
    exit 1
  fi

  if ! grep -q "$expected_title" "$tmp"; then
    echo "[ERROR] $label does not contain expected title marker: $expected_title"
    rm -f "$tmp"
    exit 1
  fi

  if grep -q "Domly Admin Web" "$tmp" && [[ "$label" != "admin" ]]; then
    echo "[ERROR] $label appears to contain admin build markers"
    rm -f "$tmp"
    exit 1
  fi

  if grep -q ">DOMLY<" "$tmp" && [[ "$label" == "admin" ]]; then
    echo "[ERROR] admin appears to contain customer build markers"
    rm -f "$tmp"
    exit 1
  fi

  if grep -q "Domly Pro" "$tmp" && [[ "$label" == "admin" ]]; then
    echo "[ERROR] admin appears to contain pro build markers"
    rm -f "$tmp"
    exit 1
  fi

  echo "[OK] $label responded"
  rm -f "$tmp"
}

check_url "customer" "$CUSTOMER_URL" "<title>DOMLY</title>"
check_url "pro" "$PRO_URL" "<title>Domly Pro</title>"
check_url "admin" "$ADMIN_URL" "<title>Domly Admin Web</title>"

echo "[OK] Post-deploy web smoke passed for customer, pro, and admin"
