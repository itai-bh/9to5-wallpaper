#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ID="org.kde.plasma.9to5"

echo "Installing KDE Plasma wallpaper extension: ${PACKAGE_ID} (9to5-wallpaper)"

# Remove the symlink left by the previous installer. Do not follow it.
USER_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
USER_PKG_ROOT="${USER_DATA_HOME}/plasma/wallpapers"
LEGACY_LINK="${USER_PKG_ROOT}/${PACKAGE_ID}"
if [ -L "${LEGACY_LINK}" ]; then
    rm -- "${LEGACY_LINK}"
fi

# Check if already installed in the writable user package root, upgrade or install cleanly via kpackagetool6
if [ -d "${LEGACY_LINK}" ] && kpackagetool6 --type Plasma/Wallpaper --package-root "${USER_PKG_ROOT}" --show "${PACKAGE_ID}" >/dev/null 2>&1; then
    echo "Upgrading existing package..."
    kpackagetool6 --type Plasma/Wallpaper -u "${SCRIPT_DIR}"
else
    echo "Installing package..."
    kpackagetool6 --type Plasma/Wallpaper -i "${SCRIPT_DIR}"
fi

# Clear Plasma QML bytecode cache
rm -rf ~/.cache/plasma* ~/.cache/qmlcache* 2>/dev/null || true

echo "Installation complete!"
echo "To preview or apply:"
echo "  Right-click desktop -> 'Configure Desktop and Wallpaper...' -> Select '9to5 Wallpaper'"
