cmake_minimum_required(VERSION 3.16)

project(9to5-wallpaper VERSION 1.0.0 LANGUAGES NONE)

find_package(ECM 6.0.0 QUIET NO_MODULE)
if (ECM_FOUND)
    set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
    include(KDEInstallDirs)
    include(KDECMakeSettings)
    include(FeatureSummary)
endif()

if (NOT KDE_INSTALL_DATADIR)
    set(KDE_INSTALL_DATADIR "${CMAKE_INSTALL_PREFIX}/share")
endif()

set(PLUGIN_ID "org.kde.plasma.9to5")
set(WALLPAPER_INSTALL_DIR "${KDE_INSTALL_DATADIR}/plasma/wallpapers/${PLUGIN_ID}")

install(FILES metadata.json DESTINATION "${WALLPAPER_INSTALL_DIR}")
install(DIRECTORY contents DESTINATION "${WALLPAPER_INSTALL_DIR}")
