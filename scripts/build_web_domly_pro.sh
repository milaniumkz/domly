#!/usr/bin/env bash
set -euo pipefail

FLUTTER_BIN=${FLUTTER_BIN:-/Volumes/PD1000/job/flutter/bin/flutter}
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/build/web-pro"
TMP_OUT_DIR="${OUT_DIR}.tmp"
REL_TMP_OUT_DIR="build/web-pro.tmp"
BUILD_STAMP="$(date +%s)"

rm -rf "$TMP_OUT_DIR"

cd "$PROJECT_DIR"

"$FLUTTER_BIN" build web --release \
  --target "lib/main_pro.dart" \
  --pwa-strategy=none \
  --no-wasm-dry-run \
  -o "$REL_TMP_OUT_DIR" \
  --dart-define=FIREBASE_API_KEY_WEB=AIzaSyATusQAZ4b14N8aUUPREx7AUU5X0dmbLw4 \
  --dart-define=FIREBASE_APP_ID_WEB=1:288330515337:web:d894db4a58831b07cd9758 \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=288330515337 \
  --dart-define=YANDEX_GEOSUGGEST_API_KEY=43a1d086-4182-4b44-9d4b-58d73fda8ee5 \
  --dart-define=YANDEX_GEOCODER_API_KEY=b8ee33e5-d419-4968-bd7c-e34b93556027

for required in index.html flutter.js flutter_bootstrap.js main.dart.js; do
  if [[ ! -f "$TMP_OUT_DIR/$required" ]]; then
    echo "Missing required web build artifact: $TMP_OUT_DIR/$required" >&2
    exit 1
  fi
done

cp "$PROJECT_DIR/web_pro/favicon.png" "$TMP_OUT_DIR/favicon.png"
cp "$PROJECT_DIR/web_pro/icons/"*.png "$TMP_OUT_DIR/icons/"

python3 - <<'PY' "$TMP_OUT_DIR/index.html"
from pathlib import Path
import sys

path = Path(sys.argv[1])
content = path.read_text()
content = content.replace("<title>domly</title>", "<title>Domly Pro</title>")
content = content.replace('content="domly"', 'content="Domly Pro"')
boot_route = """  <script>
    (function () {
      function normalizeBootRoute(value) {
        if (!value) return '';
        return value.startsWith('/') ? value : '/' + value;
      }
      function currentHashRoute() {
        var hash = window.location.hash || '';
        if (hash.indexOf('#/') !== 0) return '';
        return normalizeBootRoute(hash.substring(1).split('?')[0]);
      }
      function ensureBootRoute() {
        var url = new URL(window.location.href);
        var bootRoute = normalizeBootRoute(url.searchParams.get('boot_route') || '');
        var hashRoute = currentHashRoute();
        if (!bootRoute && hashRoute) {
          bootRoute = hashRoute;
        }
        if (bootRoute && hashRoute !== bootRoute) {
          url.hash = '#' + bootRoute;
          window.history.replaceState(null, '', url.toString());
        }
        if (bootRoute) {
          window.__domlyBootRoute = bootRoute;
          window.name = 'domly_boot_route=' + bootRoute;
        }
        if (url.searchParams.has('boot_route')) {
          url.searchParams.delete('boot_route');
          window.history.replaceState(null, '', url.toString());
        }
      }
      try {
        ensureBootRoute();
        var bootRouteGuardStartedAt = Date.now();
        var bootRouteGuard = window.setInterval(function () {
          ensureBootRoute();
          if (Date.now() - bootRouteGuardStartedAt > 4000) {
            window.clearInterval(bootRouteGuard);
          }
        }, 150);
      } catch (_) {}
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.getRegistrations().then(function (registrations) {
          registrations.forEach(function (registration) {
            if (!registration.active || !registration.active.scriptURL.includes('firebase-messaging-sw.js')) {
              registration.unregister();
            }
          });
        });
      }
      if ('caches' in window) {
        caches.keys().then(function (keys) {
          keys.forEach(function (key) { caches.delete(key); });
        });
      }
      function checkDomlyVersion() {
        try {
          fetch('/version.json?v=' + Date.now(), { cache: 'no-store' })
            .then(function (response) { return response.ok ? response.json() : null; })
            .then(function (version) {
              if (!version || !version.build) return;
              var key = 'domly_pro_web_build_version';
              var previous = window.sessionStorage.getItem(key);
              if (!previous) {
                window.sessionStorage.setItem(key, version.build);
                return;
              }
              if (previous !== version.build) {
                window.sessionStorage.setItem(key, version.build);
                window.location.reload();
              }
            })
            .catch(function () {});
        } catch (_) {}
      }
      window.setInterval(checkDomlyVersion, 20000);
      window.addEventListener('focus', checkDomlyVersion);
      document.addEventListener('visibilitychange', function () {
        if (!document.hidden) checkDomlyVersion();
      });
      checkDomlyVersion();
    })();
  </script>
"""
if "boot_route" not in content:
    content = content.replace('  <script src="flutter_bootstrap.js" async></script>', boot_route + '  <script src="flutter_bootstrap.js" async></script>')
path.write_text(content)
PY

python3 - <<'PY' "$TMP_OUT_DIR/index.html" "$TMP_OUT_DIR/flutter_bootstrap.js" "$BUILD_STAMP"
from pathlib import Path
import re
import sys

index_path = Path(sys.argv[1])
bootstrap_path = Path(sys.argv[2])
build_stamp = sys.argv[3]

index_content = index_path.read_text()
index_content = index_content.replace(
    'src="flutter_bootstrap.js" async',
    f'src="flutter_bootstrap.js?v={build_stamp}" async',
)
index_path.write_text(index_content)

content = bootstrap_path.read_text()
content = content.replace(
    '"mainJsPath":"main.dart.js"',
    f'"mainJsPath":"main.dart.js?v={build_stamp}"',
)
content = re.sub(
    r"_flutter\.loader\.load\(\{\s*serviceWorkerSettings:\s*\{.*?\}\s*\}\);",
    "if ('serviceWorker' in navigator) { navigator.serviceWorker.getRegistrations().then((registrations) => { registrations.forEach((registration) => { if (!registration.active || !registration.active.scriptURL.includes('firebase-messaging-sw.js')) registration.unregister(); }); }); }\n_flutter.loader.load({});",
    content,
    flags=re.S,
)
bootstrap_path.write_text(content)
PY

python3 - <<'PY' "$TMP_OUT_DIR/manifest.json"
from pathlib import Path
import json
import sys

path = Path(sys.argv[1])
manifest = {
    "name": "Domly Pro",
    "short_name": "Domly Pro",
    "start_url": ".",
    "display": "standalone",
    "background_color": "#F2FAF4",
    "theme_color": "#3D8A63",
    "description": "Domly Pro cleaner app.",
    "orientation": "portrait-primary",
    "prefer_related_applications": False,
    "icons": [
        {"src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png"},
        {"src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png"},
        {"src": "icons/Icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable"},
        {"src": "icons/Icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
    ],
}
path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
PY

python3 - <<'PY' "$TMP_OUT_DIR/version.json" "$BUILD_STAMP"
from pathlib import Path
import json
import sys

path = Path(sys.argv[1])
build_stamp = sys.argv[2]
path.write_text(json.dumps({
    "app": "domly-pro",
    "build": build_stamp,
}, ensure_ascii=False, indent=2))
PY

rm -rf "$OUT_DIR"
mv "$TMP_OUT_DIR" "$OUT_DIR"

echo "✓ Built pro web: $OUT_DIR"
