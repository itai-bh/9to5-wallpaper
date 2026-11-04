import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs as QtDialogs
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import org.kde.plasma.plasma5support as P5Support

Kirigami.FormLayout {
    id: root

    property alias formLayout: root

    // Signal consumed by Plasma System Settings to enable the "Apply" button
    signal configurationChanged()

    // Properties injected by Plasma wallpaper configuration dialog
    property var configDialog: null
    property var wallpaperConfiguration: null
    property var parentLayout: null

    // Safe localization helper function
    function i18nText(text) {
        if (typeof i18nd !== "undefined") {
            return i18nd("plasma_wallpaper_org.kde.plasma.9to5", text);
        }
        if (typeof i18n !== "undefined") {
            return i18n(text);
        }
        return text;
    }

    // Convert QML file:// URL to clean filesystem path
    function urlToPath(url) {
        if (!url) return "";
        var str = url.toString();
        if (str.indexOf("file://") === 0) {
            str = str.substring(7);
        }
        return decodeURIComponent(str);
    }

    // Properties prefixed with cfg_ are automatically bound by Plasma to main.xml
    property alias cfg_ActiveProfile: activeProfileHolder.text
    property alias cfg_EnableTransitions: enableTransitionsSwitch.checked
    property alias cfg_TransitionDuration: transitionSlider.value
    property alias cfg_FillMode: fillModeComboBox.currentValue
    property alias cfg_FallbackColor: fallbackColorButton.color
    property alias cfg_DynamicAccentColor: dynamicAccentSwitch.checked
    property int cfg_ProfileRevision: 0

    onCfg_ProfileRevisionChanged: {
        root.configurationChanged();
    }

    function logMessage(level, msg) {
        console.log("[9to5-wallpaper] [" + level + "] " + msg);
        commandRunner.exec(`python3 "${root.helperScript}" log --level "${level}" --message "${msg.replace(/"/g, '\\"')}"`);
    }

    function saveConfig() {
        root.logMessage("INFO", "saveConfig() invoked by Plasma System Settings. Committing profile: " + activeProfileHolder.text);
        root.cfg_ProfileRevision = root.cfg_ProfileRevision + 1;
        root.saveActiveProfile();
        if (root.wallpaperConfiguration) {
            root.wallpaperConfiguration.ProfileRevision = root.cfg_ProfileRevision;
            root.wallpaperConfiguration.ActiveProfile = activeProfileHolder.text;
            root.wallpaperConfiguration.writeConfig();
            root.logMessage("INFO", "Committed ProfileRevision=" + root.cfg_ProfileRevision + " directly to wallpaperConfiguration");
        }
    }

    // Internal path helpers
    readonly property string profilesDir: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/9to5-wallpaper/profiles"
    readonly property string helperScript: Qt.resolvedUrl("../scripts/helper.py").toString().replace("file://", "")

    // Internal Models and State
    property var activeProfileData: null
    property bool isRefreshing: false
    property int targetSlotForSinglePicker: -1

    // Hidden holder for cfg_ActiveProfile binding
    QQC2.TextField {
        id: activeProfileHolder
        visible: false
        onTextChanged: {
            root.configurationChanged();
        }
    }

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
    // ZONE 1: Profile Manager
    // -----------------------------------------------------------------------

    RowLayout {
        Kirigami.FormData.label: root.i18nText("Profile:")
        spacing: Kirigami.Units.smallSpacing

        QQC2.ComboBox {
            id: profileComboBox
            Layout.fillWidth: true
            model: profilesListModel
            textRole: "name"
            valueRole: "id"

            onActivated: {
                if (!root.isRefreshing && currentValue) {
                    activeProfileHolder.text = currentValue;
                    root.loadActiveProfile(currentValue);
                    root.configurationChanged();
                }
            }
        }

        QQC2.Button {
            icon.name: "document-new"
            text: root.i18nText("New...")
            onClicked: newProfileDialog.open()
        }

        QQC2.Button {
            icon.name: "edit-copy"
            text: root.i18nText("Duplicate")
            enabled: profileComboBox.currentIndex >= 0
            onClicked: root.duplicateCurrentProfile()
        }

        QQC2.Button {
            icon.name: "edit-delete"
            text: root.i18nText("Delete")
            enabled: profileComboBox.currentValue !== "default-aurora" && profilesListModel.count > 1
            onClicked: root.deleteCurrentProfile()
        }
    }

    RowLayout {
        Kirigami.FormData.label: root.i18nText("Dynamic HEIC:")
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            icon.name: "document-import"
            text: root.i18nText("Import .heic Preset...")
            onClicked: heicImportDialog.open()
        }

        QQC2.Button {
            icon.name: "document-export"
            text: root.i18nText("Export Current to .heic...")
            enabled: slotsListModel.count > 0
            onClicked: heicExportDialog.open()
        }

        Item {
            Layout.fillWidth: true
        }

        QQC2.BusyIndicator {
            id: busySpinner
            running: false
            visible: running
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth
        }
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: root.i18nText("24-Hour Dynamic Timeline")
    }

    // -----------------------------------------------------------------------
    // ZONE 2: Unified Timeline & Interactive Slots Track
    // -----------------------------------------------------------------------

    RowLayout {
        Kirigami.FormData.label: root.i18nText("Actions:")
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            icon.name: "insert-image"
            text: root.i18nText("Add Images...")
            onClicked: bulkImagesDialog.open()
        }

        QQC2.Button {
            icon.name: "list-add"
            text: root.i18nText("Add Blank Slot")
            onClicked: root.addTimeSlot("12:00", "")
        }

        QQC2.Button {
            icon.name: "view-grid"
            text: root.i18nText("Distribute Evenly")
            enabled: slotsListModel.count > 1
            onClicked: root.distributeSlotsEvenly()
        }

        QQC2.ComboBox {
            id: presetsComboBox
            model: [
                { text: root.i18nText("Apply a preset..."), value: "none" },
                { text: root.i18nText("2-Stage (Day / Night)"), value: "2stage" },
                { text: root.i18nText("4-Stage (Dawn / Noon / Dusk / Night)"), value: "4stage" },
                { text: root.i18nText("8-Stage (3-hour intervals)"), value: "8stage" },
                { text: root.i18nText("16-Stage (Hourly cycle)"), value: "16stage" }
            ]
            textRole: "text"
            valueRole: "value"

            onActivated: {
                if (currentValue !== "none") {
                    root.applyPreset(currentValue);
                    currentIndex = 0;
                }
            }
        }
    }

    // Horizontal Scrollable Unified Timeline
    QQC2.ScrollView {
        Kirigami.FormData.label: root.i18nText("Timeline track:")
        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 15.5
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AsNeeded
        QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AlwaysOff

        RowLayout {
            spacing: Kirigami.Units.largeSpacing

            Repeater {
                model: slotsListModel

                delegate: SlotCard {
                    slotIndex: index
                    totalSlots: slotsListModel.count
                    time: model.time
                    label: model.label || ""
                    imagePath: model.imagePath || ""
                    thumbPath: model.thumbPath || ""

                    onSlotTimeEdited: (idx, newTime) => {
                        slotsListModel.setProperty(idx, "time", newTime);
                        root.sortAndSaveSlots();
                    }

                    onSlotLabelEdited: (idx, newLabel) => {
                        slotsListModel.setProperty(idx, "label", newLabel);
                        root.saveActiveProfile();
                    }

                    onImageAssigned: (idx, newImagePath, newThumbPath) => {
                        slotsListModel.setProperty(idx, "imagePath", newImagePath);
                        slotsListModel.setProperty(idx, "thumbPath", newThumbPath);
                        root.saveActiveProfile();
                    }

                    onPickImageRequested: (idx) => {
                        root.targetSlotForSinglePicker = idx;
                        singleImageDialog.open();
                    }

                    onMoveLeftRequested: (idx) => {
                        root.swapSlots(idx, idx - 1);
                    }

                    onMoveRightRequested: (idx) => {
                        root.swapSlots(idx, idx + 1);
                    }

                    onRemoveRequested: (idx) => {
                        slotsListModel.remove(idx);
                        root.saveActiveProfile();
                    }
                }
            }

            // Quick Add Slot Card at the end of the timeline
            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 7
                implicitHeight: Kirigami.Units.gridUnit * 14
                color: Kirigami.Theme.alternateBackgroundColor
                border.color: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.15)
                radius: Kirigami.Units.cornerRadius

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.ToolButton {
                        Layout.alignment: Qt.AlignHCenter
                        icon.name: "list-add"
                        onClicked: root.addTimeSlot("12:00", "")
                    }

                    QQC2.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.i18nText("Add Slot")
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        opacity: 0.7
                    }
                }
            }
        }
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: root.i18nText("Transitions & Sizing")
    }

    // -----------------------------------------------------------------------
    // ZONE 3: Transitions & Sizing Options
    // -----------------------------------------------------------------------

    QQC2.CheckBox {
        id: enableTransitionsSwitch
        Kirigami.FormData.label: root.i18nText("Transitions:")
        text: root.i18nText("Enable smooth crossfade transitions between time slots")
        checked: true
        onCheckedChanged: root.configurationChanged()
    }

    RowLayout {
        Kirigami.FormData.label: root.i18nText("Transition speed:")
        enabled: enableTransitionsSwitch.checked
        spacing: Kirigami.Units.smallSpacing

        QQC2.Slider {
            id: transitionSlider
            from: 200
            to: 5000
            stepSize: 100
            value: 1500
            Layout.fillWidth: true
            onValueChanged: root.configurationChanged()
        }

        QQC2.Label {
            text: (transitionSlider.value / 1000.0).toFixed(1) + "s"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
        }
    }

    QQC2.ComboBox {
        id: fillModeComboBox
        Kirigami.FormData.label: root.i18nText("Positioning:")
        textRole: "label"
        valueRole: "fillMode"
        model: [
            { label: root.i18nText("Scaled and cropped (Fill Screen)"), fillMode: Image.PreserveAspectCrop },
            { label: root.i18nText("Scaled, keep proportions (Fit to Screen)"), fillMode: Image.PreserveAspectFit },
            { label: root.i18nText("Scaled (Stretch)"), fillMode: Image.Stretch },
            { label: root.i18nText("Centered (No scaling)"), fillMode: Image.Pad }
        ]
        onActivated: root.configurationChanged()
    }

    QQC2.CheckBox {
        id: dynamicAccentSwitch
        Kirigami.FormData.label: root.i18nText("Accent color:")
        text: root.i18nText("Dynamically update Plasma system accent color based on active time of day")
        checked: true
        onCheckedChanged: root.configurationChanged()
    }

    KQuickControls.ColorButton {
        id: fallbackColorButton
        Kirigami.FormData.label: root.i18nText("Fallback color:")
        dialogTitle: root.i18nText("Select Fallback Background Color")
        onColorChanged: root.configurationChanged()
    }

    // -----------------------------------------------------------------------
    // File & Action Dialogs
    // -----------------------------------------------------------------------

    // New Profile Dialog
    QQC2.Dialog {
        id: newProfileDialog
        title: root.i18nText("Create New Profile")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        anchors.centerIn: parent
        modal: true

        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            QQC2.Label {
                text: root.i18nText("Profile Name:")
            }

            QQC2.TextField {
                id: newProfileNameField
                placeholderText: root.i18nText("My Dynamic Wallpaper")
                Layout.fillWidth: true
            }
        }

        onAccepted: {
            var name = newProfileNameField.text.trim();
            if (name.length > 0) {
                root.createNewProfile(name);
                newProfileNameField.text = "";
            }
        }
    }

    // Bulk Add Images Dialog
    QtDialogs.FileDialog {
        id: bulkImagesDialog
        title: root.i18nText("Select Images to Add to Timeline")
        fileMode: QtDialogs.FileDialog.OpenFiles
        nameFilters: [
            root.i18nText("Image Files (*.jpg *.jpeg *.png *.webp *.avif *.heic)"),
            root.i18nText("All Files (*)")
        ]

        onAccepted: {
            if (selectedFiles && selectedFiles.length > 0) {
                root.logMessage("INFO", "bulkImagesDialog accepted " + selectedFiles.length + " files");
                for (var i = 0; i < selectedFiles.length; i++) {
                    var p = root.urlToPath(selectedFiles[i]);
                    // Calculate automatic sequential time distribution
                    var total = slotsListModel.count + 1;
                    var mins = Math.round(((total - 1) / total) * 1440) % 1440;
                    var hh = Math.floor(mins / 60);
                    var mm = mins % 60;
                    var timeStr = (hh < 10 ? "0" + hh : hh) + ":" + (mm < 10 ? "0" + mm : mm);

                    slotsListModel.append({
                        time: timeStr,
                        label: p.split("/").pop().replace(/\.[^/.]+$/, ""),
                        imagePath: p,
                        thumbPath: p
                    });
                }
                root.distributeSlotsEvenly();
            }
        }
    }

    // Single Image Picker Dialog
    QtDialogs.FileDialog {
        id: singleImageDialog
        title: root.i18nText("Select Wallpaper Image for Slot")
        fileMode: QtDialogs.FileDialog.OpenFile
        nameFilters: [
            root.i18nText("Image Files (*.jpg *.jpeg *.png *.webp *.avif *.heic)"),
            root.i18nText("All Files (*)")
        ]

        onAccepted: {
            if (selectedFile && root.targetSlotForSinglePicker >= 0 && root.targetSlotForSinglePicker < slotsListModel.count) {
                var cleanPath = root.urlToPath(selectedFile);
                root.logMessage("INFO", "singleImageDialog assigned image to slot " + root.targetSlotForSinglePicker + ": " + cleanPath);
                slotsListModel.setProperty(root.targetSlotForSinglePicker, "imagePath", cleanPath);
                slotsListModel.setProperty(root.targetSlotForSinglePicker, "thumbPath", cleanPath);
                root.saveActiveProfile();
                root.targetSlotForSinglePicker = -1;
            }
        }
    }

    // HEIC Import Dialog
    QtDialogs.FileDialog {
        id: heicImportDialog
        title: root.i18nText("Select Apple Dynamic .heic Wallpaper")
        fileMode: QtDialogs.FileDialog.OpenFile
        nameFilters: [
            root.i18nText("Apple Dynamic Wallpaper (*.heic *.HEIC)"),
            root.i18nText("All Files (*)")
        ]

        onAccepted: {
            if (selectedFile) {
                var cleanPath = root.urlToPath(selectedFile);
                root.logMessage("INFO", "heicImportDialog starting unpack on: " + cleanPath);
                busySpinner.running = true;

                commandRunner.exec(`python3 "${root.helperScript}" unpack-heic "${cleanPath}"`, (result) => {
                    busySpinner.running = false;
                    try {
                        var resp = JSON.parse(result.stdout);
                        if (resp.status === "success") {
                            root.logMessage("INFO", "HEIC unpack succeeded, loading profile: " + resp.data.profileId);
                            root.refreshProfilesList(resp.data.profileId);
                            root.cfg_ProfileRevision = root.cfg_ProfileRevision + 1;
                            root.configurationChanged();
                        } else {
                            root.logMessage("ERROR", "HEIC unpack failed: " + resp.error);
                        }
                    } catch (e) {
                        root.logMessage("ERROR", "Failed to parse unpack output: " + e + " (stdout=" + result.stdout + ")");
                    }
                });
            }
        }
    }

    // HEIC Export Dialog
    QtDialogs.FileDialog {
        id: heicExportDialog
        title: root.i18nText("Export Dynamic Wallpaper to .heic")
        fileMode: QtDialogs.FileDialog.SaveFile
        nameFilters: [
            root.i18nText("Apple Dynamic Wallpaper (*.heic)"),
            root.i18nText("All Files (*)")
        ]

        onAccepted: {
            if (selectedFile) {
                var targetPath = root.urlToPath(selectedFile);
                if (!targetPath.toLowerCase().endsWith(".heic")) {
                    targetPath += ".heic";
                }
                var profileId = profileComboBox.currentValue;
                busySpinner.running = true;
                commandRunner.exec(`python3 "${root.helperScript}" pack-heic --profile "${profileId}" -o "${targetPath}"`, (result) => {
                    busySpinner.running = false;
                    try {
                        var resp = JSON.parse(result.stdout);
                        if (resp.status === "success") {
                            console.log("[9to5-wallpaper] Successfully exported HEIC to:", resp.data.outputFile);
                        } else {
                            console.error("[9to5-wallpaper] Pack error:", resp.error);
                        }
                    } catch (e) {
                        console.error("[9to5-wallpaper] Failed to parse export output:", e);
                    }
                });
            }
        }
    }

    // -----------------------------------------------------------------------
    // Core Logic & Profile Management Functions
    // -----------------------------------------------------------------------

    function refreshProfilesList(selectProfileId) {
        root.isRefreshing = true;
        commandRunner.exec(`python3 "${root.helperScript}" list-profiles`, (result) => {
            try {
                var resp = JSON.parse(result.stdout);
                if (resp.status === "success") {
                    profilesListModel.clear();
                    var foundIdx = -1;
                    var targetId = selectProfileId || activeProfileHolder.text || "default-aurora";

                    for (var i = 0; i < resp.data.profiles.length; i++) {
                        var p = resp.data.profiles[i];
                        profilesListModel.append({ id: p.id, name: p.name });
                        if (p.id === targetId) {
                            foundIdx = i;
                        }
                    }

                    if (foundIdx >= 0) {
                        profileComboBox.currentIndex = foundIdx;
                    } else if (profilesListModel.count > 0) {
                        profileComboBox.currentIndex = 0;
                        targetId = profilesListModel.get(0).id;
                    }

                    root.isRefreshing = false;
                    activeProfileHolder.text = targetId;
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
        var profilePath = root.profilesDir + "/" + profileId + ".json";
        commandRunner.exec(`cat "${profilePath}"`, (result) => {
            if (result.exitCode === 0 && result.stdout.trim().length > 0) {
                try {
                    var data = JSON.parse(result.stdout);
                    root.activeProfileData = data;
                    slotsListModel.clear();
                    if (data.slots) {
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
                    console.log("[9to5-wallpaper] Config loaded profile:", profileId, "with", slotsListModel.count, "slots");
                } catch (e) {
                    console.warn("[9to5-wallpaper] Failed to parse profile JSON:", e);
                }
            }
        });
    }

    function saveActiveProfile() {
        if (!profileComboBox.currentValue) return;

        var profileId = profileComboBox.currentValue;
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
            name: profileComboBox.currentText,
            version: "1.0",
            source: "user-configured",
            transitionDuration: transitionSlider.value,
            slots: slots
        };

        var payload = JSON.stringify(profileObj);
        root.logMessage("INFO", "Saving active profile '" + profileId + "' with " + slots.length + " slots");
        commandRunner.exec(`python3 "${root.helperScript}" save-profile "${profileId}" --payload '${payload.replace(/'/g, "'\\''")}'`, (result) => {
            root.cfg_ProfileRevision = root.cfg_ProfileRevision + 1;
            root.configurationChanged();
            root.logMessage("INFO", "Profile '" + profileId + "' saved successfully, bumped cfg_ProfileRevision=" + root.cfg_ProfileRevision);
        });
    }

    function sortAndSaveSlots() {
        // Deep copy properties to avoid QObject lifecycle deletion bugs
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

        cleanSlots.sort((a, b) => {
            var parseM = (t) => {
                var p = (t || "12:00").split(":");
                return (parseInt(p[0], 10) || 0) * 60 + (parseInt(p[1], 10) || 0);
            };
            return parseM(a.time) - parseM(b.time);
        });

        slotsListModel.clear();
        for (var j = 0; j < cleanSlots.length; j++) {
            slotsListModel.append(cleanSlots[j]);
        }
        root.saveActiveProfile();
    }

    function swapSlots(fromIdx, toIdx) {
        if (fromIdx < 0 || toIdx < 0 || fromIdx >= slotsListModel.count || toIdx >= slotsListModel.count) {
            return;
        }

        var itemA = slotsListModel.get(fromIdx);
        var itemB = slotsListModel.get(toIdx);

        // Swap images and labels while retaining sequential time ordering
        var tempImg = itemA.imagePath;
        var tempThumb = itemA.thumbPath;
        var tempLabel = itemA.label;

        slotsListModel.setProperty(fromIdx, "imagePath", itemB.imagePath);
        slotsListModel.setProperty(fromIdx, "thumbPath", itemB.thumbPath);
        slotsListModel.setProperty(fromIdx, "label", itemB.label);

        slotsListModel.setProperty(toIdx, "imagePath", tempImg);
        slotsListModel.setProperty(toIdx, "thumbPath", tempThumb);
        slotsListModel.setProperty(toIdx, "label", tempLabel);

        root.saveActiveProfile();
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

        for (var i = 0; i < count; i++) {
            var totalMins = Math.round((i / count) * 1440) % 1440;
            var hh = Math.floor(totalMins / 60);
            var mm = totalMins % 60;
            var timeStr = (hh < 10 ? "0" + hh : hh) + ":" + (mm < 10 ? "0" + mm : mm);
            slotsListModel.setProperty(i, "time", timeStr);
        }
        root.saveActiveProfile();
    }

    function applyPreset(presetType) {
        slotsListModel.clear();
        var times = [];
        if (presetType === "2stage") {
            times = [{ time: "07:00", label: "Day" }, { time: "19:00", label: "Night" }];
        } else if (presetType === "4stage") {
            times = [
                { time: "06:00", label: "Dawn" },
                { time: "12:00", label: "Noon" },
                { time: "18:00", label: "Dusk" },
                { time: "22:00", label: "Night" }
            ];
        } else if (presetType === "8stage") {
            for (var h = 0; h < 24; h += 3) {
                var hhStr = (h < 10 ? "0" + h : h) + ":00";
                times.push({ time: hhStr, label: "" });
            }
        } else if (presetType === "16stage") {
            for (var i = 0; i < 16; i++) {
                var totalMins = Math.round((i / 16.0) * 1440) % 1440;
                var sh = Math.floor(totalMins / 60);
                var sm = totalMins % 60;
                times.push({
                    time: (sh < 10 ? "0" + sh : sh) + ":" + (sm < 10 ? "0" + sm : sm),
                    label: ""
                });
            }
        }

        for (var k = 0; k < times.length; k++) {
            slotsListModel.append({
                time: times[k].time,
                label: times[k].label,
                imagePath: "",
                thumbPath: ""
            });
        }
        root.saveActiveProfile();
    }

    function createNewProfile(name) {
        var newId = name.toLowerCase().replace(/[^a-z0-9]/g, "-");
        var newObj = {
            id: newId,
            name: name,
            version: "1.0",
            source: "custom-created",
            transitionDuration: transitionSlider.value,
            slots: [
                { slotIndex: 0, time: "06:00", label: "Morning", imagePath: "", thumbPath: "" },
                { slotIndex: 1, time: "12:00", label: "Afternoon", imagePath: "", thumbPath: "" },
                { slotIndex: 2, time: "18:00", label: "Evening", imagePath: "", thumbPath: "" },
                { slotIndex: 3, time: "22:00", label: "Night", imagePath: "", thumbPath: "" }
            ]
        };

        var payload = JSON.stringify(newObj);
        commandRunner.exec(`python3 "${root.helperScript}" save-profile "${newId}" --payload '${payload.replace(/'/g, "'\\''")}'`, (result) => {
            root.refreshProfilesList(newId);
        });
    }

    function duplicateCurrentProfile() {
        if (!root.activeProfileData) return;
        var currentId = profileComboBox.currentValue;
        var newId = currentId + "-copy";
        var newName = profileComboBox.currentText + " (Copy)";

        var cloned = JSON.parse(JSON.stringify(root.activeProfileData));
        cloned.id = newId;
        cloned.name = newName;

        var payload = JSON.stringify(cloned);
        commandRunner.exec(`python3 "${root.helperScript}" save-profile "${newId}" --payload '${payload.replace(/'/g, "'\\''")}'`, (result) => {
            root.refreshProfilesList(newId);
        });
    }

    function deleteCurrentProfile() {
        var currentId = profileComboBox.currentValue;
        if (!currentId || currentId === "default-aurora") return;

        commandRunner.exec(`python3 "${root.helperScript}" delete-profile "${currentId}"`, (result) => {
            root.refreshProfilesList("default-aurora");
        });
    }

    Component.onCompleted: {
        if (typeof parentLayout !== "undefined" && parentLayout) {
            twinFormLayouts.push(parentLayout);
        }
        root.refreshProfilesList(activeProfileHolder.text || "default-aurora");
    }
}
