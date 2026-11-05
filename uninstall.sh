#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ID="org.kde.plasma.9to5"

echo "Uninstalling KDE Plasma wallpaper extension: ${PACKAGE_ID}"

# Remove the symlink left by the previous installer. Do not follow it.
USER_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
USER_PKG_DIR="${USER_DATA_HOME}/plasma/wallpapers/${PACKAGE_ID}"
FIXED_LEGACY_LINK="${HOME}/.local/share/plasma/wallpapers/${PACKAGE_ID}"

removed_legacy_link=false
for link_path in "${FIXED_LEGACY_LINK}" "${USER_PKG_DIR}"; do
    if [ -L "${link_path}" ]; then
        rm -- "${link_path}"
        removed_legacy_link=true
    fi
done

if [ "${removed_legacy_link}" = false ] || [ -e "${USER_PKG_DIR}" ] || [ -e "${FIXED_LEGACY_LINK}" ]; then
    kpackagetool6 --type Plasma/Wallpaper -r "${PACKAGE_ID}"
fi
rm -rf ~/.cache/plasma* ~/.cache/qmlcache* 2>/dev/null || true

echo "Uninstalled successfully."
