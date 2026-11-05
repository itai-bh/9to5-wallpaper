#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ID="org.kde.plasma.9to5"

echo "Uninstalling KDE Plasma wallpaper extension: ${PACKAGE_ID}"

# Remove the symlink left by the previous installer. Do not follow it.
USER_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
LEGACY_LINK="${USER_DATA_HOME}/plasma/wallpapers/${PACKAGE_ID}"
if [ -L "${LEGACY_LINK}" ]; then
    rm -- "${LEGACY_LINK}"
fi

kpackagetool6 --type Plasma/Wallpaper -r "${PACKAGE_ID}"
rm -rf ~/.cache/plasma* ~/.cache/qmlcache* 2>/dev/null || true

echo "Uninstalled successfully."
