#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ID="org.kde.plasma.9to5"

echo "Installing KDE Plasma wallpaper extension: ${PACKAGE_ID} (9to5-wallpaper)"

# Check if already installed, upgrade or install cleanly via kpackagetool6
if kpackagetool6 --type Plasma/Wallpaper --show "${PACKAGE_ID}" >/dev/null 2>&1; then
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
