import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "ProfileLogic.js" as ProfileLogic

ColumnLayout {
    id: root
    spacing: Kirigami.Units.smallSpacing

    property alias formLayout: profileManager

    // Signal consumed by Plasma System Settings to enable the "Apply" button
    signal configurationChanged()

    // Properties injected by Plasma wallpaper configuration dialog
    property var configDialog: null
    property var wallpaperConfiguration: null
    property var parentLayout: null

    // Discover parent Kirigami.FormLayout from Plasma appearance container if available
    readonly property var discoveredParentLayout: {
        if (typeof appearanceRoot !== "undefined" && appearanceRoot && appearanceRoot.parentLayout) {
            return appearanceRoot.parentLayout;
        }
        if (root.parentLayout) {
            return root.parentLayout;
        }
        var p = root.parent;
        while (p) {
            if (p.parentLayout) return p.parentLayout;
            p = p.parent;
        }
        return null;
    }

    readonly property bool isWideMode: {
        if (discoveredParentLayout) {
            return discoveredParentLayout.wideMode;
        }
        return root.width >= Kirigami.Units.gridUnit * 30;
    }

    // Safe localization helper function
    function i18nText(text) {
        return (typeof i18nd !== "undefined") ? i18nd("plasma_wallpaper_org.kde.plasma.9to5", text)
             : (typeof i18n !== "undefined") ? i18n(text) : text;
    }

    // Properties prefixed with cfg_ are automatically bound by Plasma to main.xml
    property string cfg_ActiveProfile: "default-aurora"
    property alias cfg_EnableTransitions: displaySettings.enableTransitions
    property alias cfg_TransitionDuration: displaySettings.transitionDuration
    property int cfg_FillMode: Image.PreserveAspectCrop
    property alias cfg_FallbackColor: displaySettings.fallbackColor
    property alias cfg_DynamicAccentColor: displaySettings.dynamicAccentColor
    property int cfg_ProfileRevision: 0

    onCfg_ActiveProfileChanged: {
        if (!root.isRefreshing && profileManager.currentProfileId !== root.cfg_ActiveProfile) {
            profileManager.selectProfile(root.cfg_ActiveProfile);
            root.loadActiveProfile(root.cfg_ActiveProfile);
        }
    }

    function logMessage(level, msg) {
        console.log("[9to5-wallpaper] [" + level + "] " + msg);
        commandRunner.exec(`python3 "${root.helperScript}" log --level "${level}" --message "${msg.replace(/"/g, '\\"')}"`);
    }

    function saveConfig() {
        root.logMessage("INFO", "saveConfig() invoked by Plasma System Settings. Committing profile: " + root.cfg_ActiveProfile);
        root.saveActiveProfile(false);
        root.syncLockscreen();
    }

    function syncLockscreen() {
        var pId = profileManager.currentProfileId || root.cfg_ActiveProfile;
        var fillMode = root.cfg_FillMode;
        var transitions = root.cfg_EnableTransitions ? "true" : "false";
        var duration = root.cfg_TransitionDuration;
        var fallbackColor = root.cfg_FallbackColor ? root.cfg_FallbackColor.toString() : "#1e1e2e";
        var revision = root.cfg_ProfileRevision;

        var cmd = `python3 "${root.helperScript}" sync-lockscreen --profile "${pId}" --fill-mode ${fillMode} --transitions ${transitions} --duration ${duration} --fallback-color "${fallbackColor}" --revision ${revision}`;
        commandRunner.exec(cmd, (res) => {
            if (res.exitCode === 0) {
                root.logMessage("INFO", "Lock screen configuration synchronized successfully");
            } else {
                root.logMessage("WARN", "Lock screen sync reported non-zero exit: " + (res.stderr || res.stdout));
            }
        });
    }

    function refreshBootWallpaper() {
        commandRunner.exec(`python3 "${root.helperScript}" get-boot-wallpaper --user-marker "${root.bootMarkerFile}"`, (res) => {
            if (res.exitCode === 0 && res.stdout.trim().length > 0) {
                try {
                    var resp = JSON.parse(res.stdout);
                    if (resp.status === "success" && resp.data && resp.data.imagePath) {
                        root.currentBootWallpaperPath = resp.data.imagePath.replace("file://", "");
                        root.logMessage("INFO", "Current boot wallpaper recognized: " + root.currentBootWallpaperPath);
                    } else {
                        root.currentBootWallpaperPath = "";
                    }
                } catch (e) {
                    console.warn("[9to5-wallpaper] Failed to parse boot wallpaper output:", e);
                }
            }
        });
    }

    function setBootWallpaper(imagePath) {
        if (!imagePath) {
            root.logMessage("WARN", "No image assigned to slot, cannot set as boot wallpaper");
            return;
        }
        var cleanImg = imagePath.replace("file://", "");
        root.logMessage("INFO", "Requesting root permission to apply boot wallpaper: " + cleanImg);
        var cmd = `pkexec python3 "${root.helperScript}" set-boot-wallpaper "${cleanImg}" --user-marker "${root.bootMarkerFile}"`;
        commandRunner.exec(cmd, (res) => {
            if (res.exitCode === 0) {
                root.currentBootWallpaperPath = cleanImg;
                root.logMessage("INFO", "Boot wallpaper successfully applied to login manager!");
            } else {
                root.logMessage("WARN", "Set boot wallpaper canceled or failed (code=" + res.exitCode + "): " + (res.stderr || res.stdout));
            }
        });
    }

    function removeBootWallpaper() {
        root.logMessage("INFO", "Requesting root permission to remove boot wallpaper");
        var cmd = `pkexec python3 "${root.helperScript}" remove-boot-wallpaper --user-marker "${root.bootMarkerFile}"`;
        commandRunner.exec(cmd, (res) => {
            if (res.exitCode === 0) {
                root.currentBootWallpaperPath = "";
                root.logMessage("INFO", "Boot wallpaper successfully removed from login manager!");
            } else {
                root.logMessage("WARN", "Remove boot wallpaper canceled or failed (code=" + res.exitCode + "): " + (res.stderr || res.stdout));
            }
        });
    }

    function toggleBootWallpaper(imagePath) {
        if (!imagePath) {
            root.logMessage("WARN", "No image assigned to slot, cannot set as boot wallpaper");
            return;
        }
        var cleanImg = imagePath.replace("file://", "");
        if (root.currentBootWallpaperPath === cleanImg) {
            root.removeBootWallpaper();
        } else {
            root.setBootWallpaper(cleanImg);
        }
    }

    // Internal path helpers
    readonly property string profilesDir: (StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/9to5-wallpaper/profiles").replace("file://", "")
    readonly property string helperScript: Qt.resolvedUrl("../scripts/helper.py").toString().replace("file://", "")
    readonly property string bootMarkerFile: (StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/9to5-wallpaper/boot_wallpaper_marker.txt").replace("file://", "")

    // Internal Models and State
    property var activeProfileData: null
    property bool isRefreshing: false
    property string currentBootWallpaperPath: ""

    ListModel {
        id: profilesListModel
    }

    ListModel {
        id: slotsListModel
    }

    // Robust Process Executor (buffers until process exit code is available)
    P5Support.DataSource {
        id: commandRunner
        engine: "executable"
        connectedSources: []

        property var callbacks: ({})
        property var outputs: ({})

        function exec(cmd, callback) {
            if (callback && typeof callback === "function") {
                callbacks[cmd] = callback;
            }
            commandRunner.connectSource(cmd);
        }

        onNewData: function(source, data) {
            if (!outputs[source]) {
                outputs[source] = { stdout: "", stderr: "" };
            }
            if (data["stdout"]) outputs[source].stdout += data["stdout"];
            if (data["stderr"]) outputs[source].stderr += data["stderr"];

            // Only complete when exit code is present
            if (data["exit code"] !== undefined) {
                var exitCode = data["exit code"];
                var stdout = outputs[source].stdout;
                var stderr = outputs[source].stderr;
                delete outputs[source];

                if (source in callbacks) {
                    var cb = callbacks[source];
                    delete callbacks[source];
                    cb({ stdout: stdout, stderr: stderr, exitCode: exitCode });
                }
                commandRunner.disconnectSource(source);
            }
        }
    }

    // -----------------------------------------------------------------------
    // Visual Sections
    // -----------------------------------------------------------------------

    ProfileManagerSection {
        id: profileManager
        parentLayout: root.discoveredParentLayout
        twinLayout: displaySettings
        profilesModel: profilesListModel
        slotsModel: slotsListModel

        onProfileSelected: (profileId) => {
            if (!root.isRefreshing) {
                root.cfg_ActiveProfile = profileId;
                root.loadActiveProfile(profileId);
            }
        }
        onNewProfileRequested: dialogs.openNewProfileDialog()
        onDuplicateProfileRequested: root.duplicateCurrentProfile()
        onDeleteProfileRequested: root.deleteCurrentProfile()
        onImportHeicRequested: dialogs.openHeicImportDialog()
        onExportHeicRequested: dialogs.openHeicExportDialog(profileManager.currentProfileId)
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    TimelineTrackSection {
        id: timelineTrack
        slotsModel: slotsListModel
        bootWallpaperPath: root.currentBootWallpaperPath

        onAddImagesRequested: dialogs.openBulkImagesDialog()
        onAddBlankSlotRequested: root.addTimeSlot("12:00", "")
        onDistributeEvenlyRequested: root.distributeSlotsEvenly()
        onPresetSelected: (preset) => root.applyPreset(preset)
        onSlotTimeEdited: (idx, newTime) => {
            slotsListModel.setProperty(idx, "time", newTime);
            root.sortAndSaveSlots();
        }
        onSlotLabelEdited: (idx, newLabel) => {
            slotsListModel.setProperty(idx, "label", newLabel);
            root.saveActiveProfile(true);
        }
        onImageAssigned: (idx, newImg, newThumb) => {
            slotsListModel.setProperty(idx, "imagePath", newImg);
            slotsListModel.setProperty(idx, "thumbPath", newThumb);
            root.saveActiveProfile(true);
        }
        onPickImageRequested: (idx) => dialogs.openSingleImageDialog(idx)
        onMoveLeftRequested: (idx) => root.swapSlots(idx, idx - 1)
        onMoveRightRequested: (idx) => root.swapSlots(idx, idx + 1)
        onRemoveRequested: (idx) => {
            slotsListModel.remove(idx);
            root.saveActiveProfile(true);
        }
        onSetAsBootWallpaperRequested: (idx, img) => root.toggleBootWallpaper(img)
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    DisplaySettingsSection {
        id: displaySettings
        parentLayout: root.discoveredParentLayout
        twinLayout: profileManager
        cfgFillMode: root.cfg_FillMode
        onFillModeSelected: (mode) => root.cfg_FillMode = mode
    }

    ConfigDialogs {
        id: dialogs

        onProfileCreateAccepted: (name) => root.createNewProfile(name)
        onBulkImagesAccepted: (paths) => {
            for (var i = 0; i < paths.length; i++) {
                var p = paths[i];
                slotsListModel.append({
                    time: "12:00",
                    label: p.split("/").pop().replace(/\.[^/.]+$/, ""),
                    imagePath: p,
                    thumbPath: p
                });
            }
            root.distributeSlotsEvenly();
        }
        onSingleImageAccepted: (slotIdx, path) => {
            if (slotIdx >= 0 && slotIdx < slotsListModel.count) {
                root.logMessage("INFO", "Assigned image to slot " + slotIdx + ": " + path);
                slotsListModel.setProperty(slotIdx, "imagePath", path);
                slotsListModel.setProperty(slotIdx, "thumbPath", path);
                root.saveActiveProfile(true);
            }
        }
        onHeicImportAccepted: (cleanPath) => root.unpackHeicFile(cleanPath)
        onHeicExportAccepted: (profileId, targetPath) => root.packHeicFile(profileId, targetPath)
    }

    // -----------------------------------------------------------------------
    // Business Logic & Profile CRUD
    // -----------------------------------------------------------------------

    function refreshProfilesList(selectProfileId) {
        root.isRefreshing = true;
        commandRunner.exec(`python3 "${root.helperScript}" list-profiles`, (result) => {
            try {
                var resp = JSON.parse(result.stdout);
                if (resp.status === "success") {
                    profilesListModel.clear();
                    var foundIdx = -1;
                    var targetId = selectProfileId || root.cfg_ActiveProfile || (resp.data.profiles.length > 0 ? resp.data.profiles[0].id : "");

                    for (var i = 0; i < resp.data.profiles.length; i++) {
                        var p = resp.data.profiles[i];
                        profilesListModel.append({ id: p.id, name: p.name });
                        if (p.id === targetId) {
                            foundIdx = i;
                        }
                    }

                    if (foundIdx >= 0) {
                        profileManager.currentProfileIndex = foundIdx;
                    } else if (profilesListModel.count > 0) {
                        profileManager.currentProfileIndex = 0;
                        targetId = profilesListModel.get(0).id;
                    }

                    root.isRefreshing = false;
                    root.cfg_ActiveProfile = targetId;
                    console.log("[9to5-wallpaper] Config opened, active profile:", targetId, "total profiles:", resp.data.profiles.length);
                    root.loadActiveProfile(targetId);
                }
            } catch (e) {
                root.isRefreshing = false;
                console.error("[9to5-wallpaper] Failed to list profiles:", e);
            }
        });
    }

    function loadActiveProfile(profileId) {
        commandRunner.exec(`python3 "${root.helperScript}" get-profile "${profileId}"`, (result) => {
            if (result.exitCode === 0 && result.stdout.trim().length > 0) {
                try {
                    var resp = JSON.parse(result.stdout);
                    var data = (resp && resp.data) ? resp.data : resp;
                    root.activeProfileData = data;
                    slotsListModel.clear();
                    if (data && data.slots) {
                        for (var i = 0; i < data.slots.length; i++) {
                            var s = data.slots[i];
                            slotsListModel.append({
                                time: s.time,
                                label: s.label || "",
                                imagePath: s.imagePath || "",
                                thumbPath: s.thumbPath || ""
                            });
                        }
                    }
                } catch (e) {
                    console.error("[9to5-wallpaper] Failed to parse active profile:", e);
                }
            }
        });
    }

    function saveActiveProfile(bumpRevision) {
        if (bumpRevision === undefined) {
            bumpRevision = true;
        }

        var profileId = profileManager.currentProfileId || root.cfg_ActiveProfile;
        if (!profileId) return;

        var slots = [];
        for (var i = 0; i < slotsListModel.count; i++) {
            var item = slotsListModel.get(i);
            slots.push({
                slotIndex: i,
                time: item.time,
                label: item.label,
                imagePath: item.imagePath,
                thumbPath: item.thumbPath
            });
        }

        var profileObj = {
            id: profileId,
            name: (root.activeProfileData && root.activeProfileData.name) || profileId,
            slots: slots
        };

        var payload = JSON.stringify(profileObj);
        if (bumpRevision) {
            root.cfg_ProfileRevision = root.cfg_ProfileRevision + 1;
        }
        root.logMessage("INFO", "Saving active profile '" + profileId + "' with " + slots.length + " slots (bumpRevision=" + (bumpRevision ? "true" : "false") + ")");
        commandRunner.exec(`python3 "${root.helperScript}" save-profile "${profileId}" --payload '${payload.replace(/'/g, "'\\''")}'`, (result) => {
            if (result.exitCode === 0) {
                root.logMessage("INFO", "Profile '" + profileId + "' saved successfully to disk");
            } else {
                root.logMessage("ERROR", "Failed to save profile '" + profileId + "': " + (result.stderr || result.stdout));
            }
        });
    }

    function sortAndSaveSlots() {
        var cleanSlots = [];
        for (var i = 0; i < slotsListModel.count; i++) {
            var it = slotsListModel.get(i);
            cleanSlots.push({
                time: it.time,
                label: it.label || "",
                imagePath: it.imagePath || "",
                thumbPath: it.thumbPath || ""
            });
        }

        var sorted = ProfileLogic.sortSlots(cleanSlots);
        slotsListModel.clear();
        for (var j = 0; j < sorted.length; j++) {
            slotsListModel.append(sorted[j]);
        }
        root.saveActiveProfile(true);
    }

    function swapSlots(fromIdx, toIdx) {
        if (fromIdx < 0 || toIdx < 0 || fromIdx >= slotsListModel.count || toIdx >= slotsListModel.count) {
            return;
        }

        var itemA = slotsListModel.get(fromIdx);
        var itemB = slotsListModel.get(toIdx);

        var tempImg = itemA.imagePath;
        var tempThumb = itemA.thumbPath;
        var tempLabel = itemA.label;

        slotsListModel.setProperty(fromIdx, "imagePath", itemB.imagePath);
        slotsListModel.setProperty(fromIdx, "thumbPath", itemB.thumbPath);
        slotsListModel.setProperty(fromIdx, "label", itemB.label);

        slotsListModel.setProperty(toIdx, "imagePath", tempImg);
        slotsListModel.setProperty(toIdx, "thumbPath", tempThumb);
        slotsListModel.setProperty(toIdx, "label", tempLabel);

        root.saveActiveProfile(true);
    }

    function addTimeSlot(time, imagePath) {
        slotsListModel.append({
            time: time,
            label: "",
            imagePath: imagePath,
            thumbPath: imagePath
        });
        root.sortAndSaveSlots();
    }

    function distributeSlotsEvenly() {
        var count = slotsListModel.count;
        if (count === 0) return;
        var intervals = ProfileLogic.computeEvenIntervals(count);
        for (var i = 0; i < count; i++) {
            slotsListModel.setProperty(i, "time", intervals[i]);
        }
        root.saveActiveProfile(true);
    }

    function applyPreset(presetType) {
        slotsListModel.clear();
        var times = ProfileLogic.getPresetSlots(presetType);
        for (var k = 0; k < times.length; k++) {
            slotsListModel.append({
                time: times[k].time,
                label: times[k].label,
                imagePath: "",
                thumbPath: ""
            });
        }
        root.saveActiveProfile(true);
    }

    function createNewProfile(name) {
        var newId = ProfileLogic.sanitizeProfileId(name);
        var newObj = {
            id: newId,
            name: name,
            slots: [
                { slotIndex: 0, time: "06:00", label: "Morning", imagePath: "", thumbPath: "" },
                { slotIndex: 1, time: "12:00", label: "Noon", imagePath: "", thumbPath: "" },
                { slotIndex: 2, time: "18:00", label: "Sunset", imagePath: "", thumbPath: "" },
                { slotIndex: 3, time: "22:00", label: "Night", imagePath: "", thumbPath: "" }
            ]
        };

        var payload = JSON.stringify(newObj);
        commandRunner.exec(`python3 "${root.helperScript}" save-profile "${newId}" --payload '${payload.replace(/'/g, "'\\''")}'`, (result) => {
            if (result.exitCode === 0) {
                root.cfg_ActiveProfile = newId;
                root.cfg_ProfileRevision = root.cfg_ProfileRevision + 1;
                root.refreshProfilesList(newId);
            } else {
                root.logMessage("ERROR", "Failed to create profile: " + (result.stderr || result.stdout));
            }
        });
    }

    function duplicateCurrentProfile() {
        if (!root.activeProfileData) return;
        var currentId = profileManager.currentProfileId || root.cfg_ActiveProfile;
        var newId = currentId + "-copy";
        var newName = profileManager.currentProfileText + " (Copy)";

        var cloned = JSON.parse(JSON.stringify(root.activeProfileData));
        cloned.id = newId;
        cloned.name = newName;

        var payload = JSON.stringify(cloned);
        commandRunner.exec(`python3 "${root.helperScript}" save-profile "${newId}" --payload '${payload.replace(/'/g, "'\\''")}'`, (result) => {
            if (result.exitCode === 0) {
                root.cfg_ActiveProfile = newId;
                root.cfg_ProfileRevision = root.cfg_ProfileRevision + 1;
                root.refreshProfilesList(newId);
            } else {
                root.logMessage("ERROR", "Failed to duplicate profile: " + (result.stderr || result.stdout));
            }
        });
    }

    function deleteCurrentProfile() {
        var currentId = profileManager.currentProfileId || root.cfg_ActiveProfile;
        if (!currentId || profilesListModel.count <= 1) return;

        var nextId = "";
        var currentIndex = profileManager.currentProfileIndex;
        if (currentIndex >= 0) {
            if (currentIndex + 1 < profilesListModel.count) {
                nextId = profilesListModel.get(currentIndex + 1).id;
            } else if (currentIndex - 1 >= 0) {
                nextId = profilesListModel.get(currentIndex - 1).id;
            }
        }
        if (!nextId) {
            for (var i = 0; i < profilesListModel.count; i++) {
                var item = profilesListModel.get(i);
                if (item.id !== currentId) {
                    nextId = item.id;
                    break;
                }
            }
        }

        commandRunner.exec(`python3 "${root.helperScript}" delete-profile "${currentId}"`, (result) => {
            if (result.exitCode === 0) {
                root.cfg_ActiveProfile = nextId;
                root.cfg_ProfileRevision = root.cfg_ProfileRevision + 1;
                root.refreshProfilesList(nextId);
            } else {
                root.logMessage("ERROR", "Failed to delete profile: " + (result.stderr || result.stdout));
            }
        });
    }

    function unpackHeicFile(cleanPath) {
        root.logMessage("INFO", "heicImportDialog starting unpack on: " + cleanPath);
        profileManager.isBusy = true;

        commandRunner.exec(`python3 "${root.helperScript}" unpack-heic "${cleanPath}"`, (result) => {
            profileManager.isBusy = false;
            try {
                var resp = JSON.parse(result.stdout);
                if (resp.status === "success") {
                    root.logMessage("INFO", "HEIC unpack succeeded, loading profile: " + resp.data.profileId);
                    root.cfg_ActiveProfile = resp.data.profileId;
                    root.cfg_ProfileRevision = root.cfg_ProfileRevision + 1;
                    root.refreshProfilesList(resp.data.profileId);
                } else {
                    root.logMessage("ERROR", "HEIC unpack failed: " + resp.error);
                }
            } catch (e) {
                root.logMessage("ERROR", "Failed to parse unpack output: " + e + " (stdout=" + result.stdout + ")");
            }
        });
    }

    function packHeicFile(profileId, targetPath) {
        profileManager.isBusy = true;
        commandRunner.exec(`python3 "${root.helperScript}" pack-heic --profile "${profileId}" -o "${targetPath}"`, (result) => {
            profileManager.isBusy = false;
            try {
                var resp = JSON.parse(result.stdout);
                if (resp.status === "success") {
                    root.logMessage("INFO", "Successfully exported HEIC to: " + resp.data.outputFile);
                } else {
                    root.logMessage("ERROR", "Pack error: " + resp.error);
                }
            } catch (e) {
                root.logMessage("ERROR", "Failed to parse export output: " + e);
            }
        });
    }

    Component.onCompleted: {
        root.refreshProfilesList(root.cfg_ActiveProfile || "");
        root.refreshBootWallpaper();
        root.syncLockscreen();
    }
}
