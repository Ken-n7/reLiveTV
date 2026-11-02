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
# menu icon (GNOME matches the window to it through StartupWMClass = the GTK app id)
icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
mkdir -p "$icon_dir"
cp linux/relivetv.png "$icon_dir/relivetv.png"
desktop="$HOME/.local/share/applications/tv-channels.desktop"
if [ -f "$desktop" ]; then
  sed -i 's/^Icon=.*/Icon=relivetv/' "$desktop"
  grep -q '^StartupWMClass=' "$desktop" || echo 'StartupWMClass=com.ken.tv_channels' >> "$desktop"
fi
echo "installed to $dest"
