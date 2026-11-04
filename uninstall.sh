#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ID="org.kde.plasma.9to5"
TARGET_DIR="${HOME}/.local/share/plasma/wallpapers/${PACKAGE_ID}"

if [ -L "${TARGET_DIR}" ] || [ -d "${TARGET_DIR}" ]; then
    rm -rf "${TARGET_DIR}"
    echo "Removed ${TARGET_DIR}"
else
    echo "Package ${PACKAGE_ID} was not found in ${HOME}/.local/share/plasma/wallpapers"
fi
