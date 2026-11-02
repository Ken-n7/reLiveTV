#!/usr/bin/env bash
# Build the dev (debug) app and install it where the "TV Channels" menu shortcut
# points. Integration tests rebuild build/linux/... with test code, so the
# shortcut must not run straight from the build folder.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build linux --debug
dest="$HOME/.local/opt/tv-channels"
rm -rf "$dest.new" && mkdir -p "$(dirname "$dest")"
cp -r build/linux/x64/debug/bundle "$dest.new"
rm -rf "$dest" && mv "$dest.new" "$dest"
echo "installed to $dest"
