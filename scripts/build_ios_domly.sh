#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_FLUTTER_DIR="$ROOT_DIR/ios/Flutter"
FLUTTER_BIN=${FLUTTER_BIN:-flutter}

cat > "$IOS_FLUTTER_DIR/Release.xcconfig" <<'CFG'
#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"
#include "Generated.xcconfig"
PRODUCT_BUNDLE_IDENTIFIER = com.domly.customer
APP_DISPLAY_NAME = DOMLY
ASSETCATALOG_COMPILER_APPICON_NAME = AppIconDomly
MAPS_API_KEY =
CFG

if [[ -n "${MAPS_API_KEY:-}" ]]; then
  echo "MAPS_API_KEY = ${MAPS_API_KEY}" >> "$IOS_FLUTTER_DIR/Release.xcconfig"
fi

"$FLUTTER_BIN" build ios \
  --release \
  ${MAPS_API_KEY:+--dart-define=MAPS_API_KEY=$MAPS_API_KEY} \
  --dart-define=YANDEX_GEOSUGGEST_API_KEY=43a1d086-4182-4b44-9d4b-58d73fda8ee5 \
  --dart-define=YANDEX_GEOCODER_API_KEY=b8ee33e5-d419-4968-bd7c-e34b93556027 \
  ${WAPPI_TOKEN:+--dart-define=WAPPI_TOKEN=$WAPPI_TOKEN} \
  ${WAPPI_PROFILE_ID:+--dart-define=WAPPI_PROFILE_ID=$WAPPI_PROFILE_ID} \
  --target lib/main_customer.dart
