#!/usr/bin/env bash
set -euo pipefail

FLUTTER_BIN=${FLUTTER_BIN:-flutter}

"$FLUTTER_BIN" build apk --release --flavor domlyAdmin \
  --target lib/main_admin_web.dart \
  --dart-define=FIREBASE_API_KEY_ANDROID=AIzaSyAzPWe_eZjvjRlJ3BvqT2c9y0L6nSQSIw8 \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=288330515337 \
  --dart-define=FIREBASE_APP_ID_ANDROID_CUSTOMER=1:288330515337:android:272dcba306b05783cd9758 \
  --dart-define=WAPPI_TOKEN=56d9046372837699b85460a558476f78beb8f1bf \
  --dart-define=WAPPI_PROFILE_ID=7b6095b5-c20c

echo "✓ Built: build/app/outputs/flutter-apk/app-domlyadmin-release.apk"
