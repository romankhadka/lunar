#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "--> swift build -c release"
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
  BIN_PATH=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
else
  swift build -c release   # fall back to native arch
  BIN_PATH=$(swift build -c release --show-bin-path)
fi
APP_ROOT="build/Lunar.app"
rm -rf "$APP_ROOT"
mkdir -p "$APP_ROOT/Contents/MacOS"
mkdir -p "$APP_ROOT/Contents/Resources/phases"

cp "$BIN_PATH/Lunar"                    "$APP_ROOT/Contents/MacOS/Lunar"
cp Sources/Lunar/Info.plist             "$APP_ROOT/Contents/Info.plist"
cp Sources/Lunar/Resources/phases/*.png "$APP_ROOT/Contents/Resources/phases/"
printf 'APPL????' > "$APP_ROOT/Contents/PkgInfo"

# SwiftPM emits a resource bundle next to the binary; copy that too so
# Bundle.module resolves at runtime.
if [ -d "$BIN_PATH/Lunar_Lunar.bundle" ]; then
  cp -R "$BIN_PATH/Lunar_Lunar.bundle" "$APP_ROOT/Contents/Resources/"
fi

echo "--> codesign (ad-hoc)"
codesign --force --deep --sign - "$APP_ROOT"

echo "Built $APP_ROOT"
