#!/usr/bin/env bash
set -euo pipefail

FLUTTER_BIN=${FLUTTER_BIN:-flutter}
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" == "--unsigned" ]]; then
  export ORG_GRADLE_PROJECT_domlyUnsignedAdmin=true
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--unsigned]" >&2
  exit 2
elif [[ ! -f "$PROJECT_DIR/android/key.properties" ]]; then
  echo "Release signing configuration missing: android/key.properties. Use --unsigned only to prepare an APK for signing." >&2
  exit 1
fi

cd "$PROJECT_DIR"
"$FLUTTER_BIN" build apk --release --flavor domlyAdmin \
  --target lib/main_admin_web.dart \
  --dart-define=FIREBASE_API_KEY_ANDROID=AIzaSyAzPWe_eZjvjRlJ3BvqT2c9y0L6nSQSIw8 \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=288330515337 \
  --dart-define=FIREBASE_APP_ID_ANDROID_CUSTOMER=1:288330515337:android:272dcba306b05783cd9758

echo "✓ Built: build/app/outputs/flutter-apk/app-domlyadmin-release.apk"
