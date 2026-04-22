#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build.sh

DEST="$HOME/Applications/Lunar.app"
mkdir -p "$HOME/Applications"

# Kill any currently-running copy so we can replace the bundle.
pkill -x Lunar || true

rm -rf "$DEST"
cp -R build/Lunar.app "$DEST"

echo "Installed to $DEST"
echo "To launch: open \"$DEST\""
echo "To enable launch-at-login, open the app once and toggle the menu item."
