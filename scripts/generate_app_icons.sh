#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOMLY_SRC="$ROOT_DIR/assets/Rectangle.png"
PRO_SRC="$ROOT_DIR/assets/logo_pro.png"

generate_ios_set() {
  local src="$1"
  local out_dir="$2"

  while IFS=: read -r filename size; do
    sips -z "$size" "$size" "$src" --out "$out_dir/$filename" >/dev/null
  done <<'EOF'
Icon-App-20x20@1x.png:20
Icon-App-20x20@2x.png:40
Icon-App-20x20@3x.png:60
Icon-App-29x29@1x.png:29
Icon-App-29x29@2x.png:58
Icon-App-29x29@3x.png:87
Icon-App-40x40@1x.png:40
Icon-App-40x40@2x.png:80
Icon-App-40x40@3x.png:120
Icon-App-60x60@2x.png:120
Icon-App-60x60@3x.png:180
Icon-App-76x76@1x.png:76
Icon-App-76x76@2x.png:152
Icon-App-83.5x83.5@2x.png:167
Icon-App-1024x1024@1x.png:1024
EOF
}

generate_android_set() {
  local src="$1"
  local res_root="$2"

  while IFS=: read -r folder size; do
    sips -z "$size" "$size" "$src" --out "$res_root/$folder/ic_launcher.png" >/dev/null
  done <<'EOF'
mipmap-mdpi:48
mipmap-hdpi:72
mipmap-xhdpi:96
mipmap-xxhdpi:144
mipmap-xxxhdpi:192
EOF
}

generate_ios_set "$DOMLY_SRC" "$ROOT_DIR/ios/Runner/Assets.xcassets/AppIconDomly.appiconset"
generate_ios_set "$PRO_SRC" "$ROOT_DIR/ios/Runner/Assets.xcassets/AppIconDomlyPro.appiconset"
generate_android_set "$DOMLY_SRC" "$ROOT_DIR/android/app/src/domly/res"
generate_android_set "$PRO_SRC" "$ROOT_DIR/android/app/src/domlyPro/res"

echo "App icons generated successfully."
