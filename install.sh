#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ID="org.kde.plasma.9to5"
TARGET_DIR="${HOME}/.local/share/plasma/wallpapers/${PACKAGE_ID}"

echo "Installing KDE Plasma wallpaper extension: ${PACKAGE_ID} (9to5-wallpaper)"

# Mode: symlink (recommended for rapid development and testing)
mkdir -p "${HOME}/.local/share/plasma/wallpapers"
ln -sfn "${SCRIPT_DIR}" "${TARGET_DIR}"

echo "Successfully linked to ${TARGET_DIR}"
echo ""
echo "To test or verify installation:"
echo "  kpackagetool6 --type Plasma/Wallpaper --show ${PACKAGE_ID}"
echo ""
echo "To preview or apply:"
echo "  Right-click desktop -> 'Configure Desktop and Wallpaper...' -> Select '9to5 Wallpaper'"
