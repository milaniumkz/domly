#!/usr/bin/env bash
set -euo pipefail

FLUTTER_BIN=${FLUTTER_BIN:-flutter}
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"


cd "$PROJECT_DIR"
"$FLUTTER_BIN" build apk --release --target lib/main_pro.dart --flavor domlyPro \
  --dart-define=FIREBASE_API_KEY_ANDROID=AIzaSyAzPWe_eZjvjRlJ3BvqT2c9y0L6nSQSIw8 \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=288330515337 \
  --dart-define=FIREBASE_APP_ID_ANDROID_PRO=1:288330515337:android:e34939ba65c8e796cd9758

# Restore main.dart to customer (default)

echo "✓ Built: build/app/outputs/flutter-apk/app-domlypro-release.apk"
