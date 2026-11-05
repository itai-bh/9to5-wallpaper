#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ID="org.kde.plasma.9to5"

echo "Uninstalling KDE Plasma wallpaper extension: ${PACKAGE_ID}"

# Remove the symlink left by the previous installer. Do not follow it.
USER_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
USER_PKG_ROOT="${USER_DATA_HOME}/plasma/wallpapers"
USER_PKG_DIR="${USER_PKG_ROOT}/${PACKAGE_ID}"
FIXED_PKG_ROOT="${HOME}/.local/share/plasma/wallpapers"
FIXED_LEGACY_LINK="${FIXED_PKG_ROOT}/${PACKAGE_ID}"

removed_legacy_link=false
for link_path in "${FIXED_LEGACY_LINK}" "${USER_PKG_DIR}"; do
    if [ -L "${link_path}" ]; then
        rm -- "${link_path}"
        removed_legacy_link=true
    fi
done

removed_pkg=false
if [ -e "${USER_PKG_DIR}" ]; then
    kpackagetool6 --type Plasma/Wallpaper --packageroot "${USER_PKG_ROOT}" -r "${PACKAGE_ID}"
    removed_pkg=true
fi
if [ "${FIXED_PKG_ROOT}" != "${USER_PKG_ROOT}" ] && [ -e "${FIXED_LEGACY_LINK}" ]; then
    kpackagetool6 --type Plasma/Wallpaper --packageroot "${FIXED_PKG_ROOT}" -r "${PACKAGE_ID}"
    removed_pkg=true
fi
if [ "${removed_legacy_link}" = false ] && [ "${removed_pkg}" = false ]; then
    kpackagetool6 --type Plasma/Wallpaper -r "${PACKAGE_ID}"
fi

lockscreen_plugin="$(kreadconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin 2>/dev/null || true)"
if [ "${lockscreen_plugin}" = "${PACKAGE_ID}" ]; then
    kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin --delete
fi

rm -rf ~/.cache/plasma* ~/.cache/qmlcache* 2>/dev/null || true

echo "Uninstalled successfully."
