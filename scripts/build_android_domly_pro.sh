#!/usr/bin/env bash
set -euo pipefail

FLUTTER_BIN=${FLUTTER_BIN:-flutter}
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Ensure main.dart uses pro entrypoint
sed -i '' 's/await customerMain();/await proMain();/' "$PROJECT_DIR/lib/main.dart"

"$FLUTTER_BIN" build apk --release --flavor domlyPro \
  --dart-define=FIREBASE_API_KEY_ANDROID=AIzaSyAzPWe_eZjvjRlJ3BvqT2c9y0L6nSQSIw8 \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=288330515337 \
  --dart-define=FIREBASE_APP_ID_ANDROID_PRO=1:288330515337:android:e34939ba65c8e796cd9758 \
  --dart-define=YANDEX_GEOSUGGEST_API_KEY=43a1d086-4182-4b44-9d4b-58d73fda8ee5 \
  --dart-define=YANDEX_GEOCODER_API_KEY=b8ee33e5-d419-4968-bd7c-e34b93556027 \
  --dart-define=WAPPI_TOKEN=56d9046372837699b85460a558476f78beb8f1bf \
  --dart-define=WAPPI_PROFILE_ID=7b6095b5-c20c

# Restore main.dart to customer (default)
sed -i '' 's/await proMain();/await customerMain();/' "$PROJECT_DIR/lib/main.dart"

echo "✓ Built: build/app/outputs/flutter-apk/app-domlypro-release.apk"
