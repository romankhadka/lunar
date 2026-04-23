#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Build a release .app first.
./scripts/build.sh

VERSION="${1:-1.0}"
APP="build/Lunar.app"
STAGE="build/dmg-stage"
DMG="build/Lunar-${VERSION}.dmg"

if [ ! -d "$APP" ]; then
    echo "Expected $APP to exist after build.sh. Aborting." >&2
    exit 1
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Lunar.app"
ln -s /Applications "$STAGE/Applications"

echo "--> hdiutil create $DMG"
hdiutil create \
    -volname "Lunar ${VERSION}" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG"

rm -rf "$STAGE"
echo "Built $DMG"
ls -lh "$DMG"
