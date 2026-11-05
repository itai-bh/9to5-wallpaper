#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ID="org.kde.plasma.9to5"

echo "Uninstalling KDE Plasma wallpaper extension: ${PACKAGE_ID}"

kpackagetool6 --type Plasma/Wallpaper -r "${PACKAGE_ID}" 2>/dev/null || true
rm -rf ~/.cache/plasma* ~/.cache/qmlcache* 2>/dev/null || true

echo "Uninstalled successfully."
