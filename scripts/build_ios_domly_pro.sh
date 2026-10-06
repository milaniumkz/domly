#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_FLUTTER_DIR="$ROOT_DIR/ios/Flutter"
FLUTTER_BIN=${FLUTTER_BIN:-flutter}

cat > "$IOS_FLUTTER_DIR/Release.xcconfig" <<'CFG'
#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"
#include "Generated.xcconfig"
PRODUCT_BUNDLE_IDENTIFIER = com.domly.pro
APP_DISPLAY_NAME = Domly Pro
ASSETCATALOG_COMPILER_APPICON_NAME = AppIconDomlyPro
MAPS_API_KEY =
DOMLY_URL_SCHEME = domly-pro
CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements
APS_ENVIRONMENT = production
CFG

if [[ -n "${MAPS_API_KEY:-}" ]]; then
  echo "MAPS_API_KEY = ${MAPS_API_KEY}" >> "$IOS_FLUTTER_DIR/Release.xcconfig"
fi

cd "$ROOT_DIR"
"$FLUTTER_BIN" build ios \
  --release \
  ${MAPS_API_KEY:+--dart-define=MAPS_API_KEY=$MAPS_API_KEY} \
  --target lib/main_pro.dart
