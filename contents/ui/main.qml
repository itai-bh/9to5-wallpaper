import QtQuick
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

WallpaperItem {
    id: root

    // Safe configuration accessors with robust defaults
    readonly property var cfg: root.configuration || null
    readonly property color cfgFallbackColor: (cfg && cfg.FallbackColor) ? cfg.FallbackColor : "#1e1e2e"
    readonly property bool cfgDynamicAccentColor: (cfg && cfg.DynamicAccentColor !== undefined) ? cfg.DynamicAccentColor : true
    readonly property bool cfgEnableTransitions: (cfg && cfg.EnableTransitions !== undefined) ? cfg.EnableTransitions : true
    readonly property int cfgFillMode: (cfg && cfg.FillMode !== undefined) ? cfg.FillMode : Image.PreserveAspectCrop
    readonly property int cfgTransitionDuration: (cfg && cfg.TransitionDuration !== undefined) ? cfg.TransitionDuration : 1500
    readonly property string cfgActiveProfile: (cfg && cfg.ActiveProfile) ? cfg.ActiveProfile : "default-aurora"
    readonly property int cfgProfileRevision: (cfg && cfg.ProfileRevision !== undefined) ? cfg.ProfileRevision : 0

    onCfgActiveProfileChanged: {
        console.log("[9to5-wallpaper] ActiveProfile configuration property changed to:", cfgActiveProfile);
        root.reloadProfile();
    }

    onCfgProfileRevisionChanged: {
        console.log("[9to5-wallpaper] ProfileRevision configuration property changed to:", cfgProfileRevision);
        root.reloadProfile();
    }

    // Dynamic accent color support
    accentColor: cfgDynamicAccentColor ? activeAccentColor : cfgFallbackColor
    property color activeAccentColor: "#89b4fa"

    // Path constants
    readonly property string profilesDir: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/9to5-wallpaper/profiles"
    readonly property string helperScript: Qt.resolvedUrl("../scripts/helper.py").toString().replace("file://", "")

    // Internal State
    property var activeProfile: null
    property var sortedSlots: []
    property var currentSlot: null
    property string currentImagePath: ""
    property bool isInitialized: false

    // Base background fallback
    Rectangle {
        id: fallbackBackground
        anchors.fill: parent
        color: root.cfgFallbackColor
        z: 0
    }

    // Dual-Buffer Display Layer 1: Primary Image (Idle Active Frame)
    Image {
        id: primaryImage
        anchors.fill: parent
        fillMode: root.cfgFillMode
        asynchronous: true
        cache: false
        opacity: 1.0
        z: 1

        onStatusChanged: {
            if (status === Image.Ready) {
                root.logMessage("INFO", "Primary image loaded successfully: " + source);
            } else if (status === Image.Error) {
                root.logMessage("ERROR", "Primary image failed to load: " + source);
            }
        }
    }

    // Dual-Buffer Display Layer 2: Secondary Image (Crossfade Target Frame)
    Image {
        id: secondaryImage
        anchors.fill: parent
        fillMode: root.cfgFillMode
        asynchronous: true
        cache: false
        opacity: 0.0
        z: 2

        onStatusChanged: {
            if (status === Image.Ready) {
                root.logMessage("INFO", "Secondary image ready for crossfade: " + source);
            } else if (status === Image.Error) {
                root.logMessage("ERROR", "Secondary image failed to load: " + source);
                opacityAnimator.stop();
                secondaryImage.opacity = 0.0;
                secondaryImage.source = "";
            }
        }

        NumberAnimation on opacity {
            id: opacityAnimator
            running: false
            from: 0.0
            to: 1.0
            duration: Math.max(100, root.cfgTransitionDuration)
            easing.type: Easing.InOutQuad

            onFinished: {
                // Commit transition to primaryImage and immediately purge secondaryImage texture
                primaryImage.source = secondaryImage.source;
                primaryImage.opacity = 1.0;
                root.currentImagePath = secondaryImage.source.toString();

                // Clear secondaryImage to free VRAM/RAM
                secondaryImage.source = "";
                secondaryImage.opacity = 0.0;
            }
        }
    }

    // External URL / File Dragged onto Desktop
    onOpenUrlRequested: (url) => {
        var rawStr = url.toString();
        if (rawStr.indexOf("file://") === 0) {
            rawStr = rawStr.substring(7);
        }
        var path = decodeURIComponent(rawStr);
        if (path.toLowerCase().endsWith(".heic")) {
            console.log("[9to5-wallpaper] Importing dropped HEIC dynamic wallpaper:", path);
            commandRunner.exec(`python3 "${root.helperScript}" unpack-heic "${path}"`, (result) => {
                try {
                    var resp = JSON.parse(result.stdout);
                    if (resp.status === "success" && root.cfg) {
                        root.cfg.ActiveProfile = resp.data.profileId;
                        root.cfg.writeConfig();
                        root.reloadProfile();
                    }
                } catch (e) {
                    console.error("[9to5-wallpaper] Failed to parse unpack output:", e);
                }
            });
        }
    }

    // -----------------------------------------------------------------------
    // Adaptive Delta Scheduling & Resync Engine
    // -----------------------------------------------------------------------

    // Event-Delta Timer: Sleeps until the exact millisecond of the next transition
    Timer {
        id: deltaTimer
        repeat: false
        interval: 60000
        onTriggered: {
            root.updateScheduledSlot(true);
        }
    }

    // Low-Priority Heartbeat (fires once every 60s)
    Timer {
        id: heartbeatTimer
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            root.checkClockSync();
        }
    }

    // Helper process executor
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
    // Core Logic Functions
    // -----------------------------------------------------------------------

    function logMessage(level, msg) {
        if (level === "ERROR") {
            console.error("[9to5-wallpaper] [" + level + "] " + msg);
        } else if (level === "WARN") {
            console.warn("[9to5-wallpaper] [" + level + "] " + msg);
        } else {
            console.log("[9to5-wallpaper] [" + level + "] " + msg);
        }
    }

    function timeToMinutes(timeStr) {
        if (!timeStr) return 0;
        var parts = timeStr.split(":");
        var hh = parseInt(parts[0], 10) || 0;
        var mm = parseInt(parts[1], 10) || 0;
        return (hh * 60 + mm) % 1440;
    }

    function sortProfileSlots() {
        if (!root.activeProfile || !root.activeProfile.slots || root.activeProfile.slots.length === 0) {
            root.sortedSlots = [];
            return;
        }
        root.sortedSlots = root.activeProfile.slots.slice().sort((a, b) => {
            return root.timeToMinutes(a.time) - root.timeToMinutes(b.time);
        });
    }

    function reloadProfile() {
        var profileId = root.cfgActiveProfile;
        root.currentSlot = null;
        root.sortedSlots = [];
        root.currentImagePath = "";

        root.logMessage("INFO", "reloadProfile() requested for profile: " + profileId);
        commandRunner.exec(`python3 "${root.helperScript}" get-profile "${profileId}"`, (result) => {
            if (result.exitCode === 0 && result.stdout.trim().length > 0) {
                try {
                    var resp = JSON.parse(result.stdout);
                    if (resp.status === "success" && resp.data) {
                        root.activeProfile = resp.data;
                        root.sortProfileSlots();
                        root.logMessage("INFO", "Active profile loaded successfully: " + root.activeProfile.id + " ('" + root.activeProfile.name + "') with " + (root.activeProfile.slots ? root.activeProfile.slots.length : 0) + " slots");
                        root.updateScheduledSlot(false);
                        return;
                    }
                } catch (e) {
                    root.logMessage("WARN", "Failed to parse get-profile JSON: " + e);
                }
            }

            // Fallback to bootstrap defaults
            root.logMessage("WARN", "Profile '" + profileId + "' unavailable, initializing defaults...");
            commandRunner.exec(`python3 "${root.helperScript}" init-defaults`, (initRes) => {
                try {
                    var res = JSON.parse(initRes.stdout);
                    if (res.status === "success" && res.data && res.data.profile) {
                        root.activeProfile = res.data.profile;
                        root.sortProfileSlots();
                        root.logMessage("INFO", "Default profile initialized with " + (root.activeProfile.slots ? root.activeProfile.slots.length : 0) + " slots");
                        root.updateScheduledSlot(false);
                    }
                } catch (err) {
                    root.logMessage("ERROR", "Failed to initialize default profile: " + err);
                }
            });
        });
    }

    function updateScheduledSlot(animate) {
        if (!root.sortedSlots || root.sortedSlots.length === 0) {
            console.warn("[9to5-wallpaper] updateScheduledSlot called but profile has no slots");
            return;
        }

        var slots = root.sortedSlots;

        var now = new Date();
        var currentMins = now.getHours() * 60 + now.getMinutes();
        var currentSecs = now.getSeconds();
        var currentMillis = now.getMilliseconds();

        // 1. Find active slot: latest slot where slotMins <= currentMins
        var activeIdx = -1;
        for (var i = 0; i < slots.length; i++) {
            if (root.timeToMinutes(slots[i].time) <= currentMins) {
                activeIdx = i;
            } else {
                break;
            }
        }

        // Wrap around to previous day's last slot if before the first morning slot
        if (activeIdx === -1) {
            activeIdx = slots.length - 1;
        }

        var selectedSlot = slots[activeIdx];
        var nextIdx = (activeIdx + 1) % slots.length;
        var nextSlot = slots[nextIdx];

        // 2. Calculate delta milliseconds until nextSlot
        var nextMins = root.timeToMinutes(nextSlot.time);
        var deltaMinutes = (nextMins > currentMins) ? (nextMins - currentMins) : (1440 - currentMins + nextMins);
        var deltaMs = (deltaMinutes * 60 - currentSecs) * 1000 - currentMillis;
        if (deltaMs <= 500) {
            deltaMs = 1000;
        }

        // Schedule delta timer
        deltaTimer.stop();
        deltaTimer.interval = deltaMs;
        deltaTimer.start();

        console.log("[9to5-wallpaper] Active slot:", selectedSlot.time, "(" + (selectedSlot.label || "unlabeled") + "), next transition at:", nextSlot.time, "in", Math.round(deltaMs / 1000) + "s");

        // 3. Apply active image
        root.currentSlot = selectedSlot;
        var targetSource = selectedSlot.imagePath ? ("file://" + selectedSlot.imagePath) : "";

        if (!root.isInitialized || !animate || !root.cfgEnableTransitions || root.cfgTransitionDuration <= 0) {
            root.isInitialized = true;
            console.log("[9to5-wallpaper] Displaying image immediately (no animation):", targetSource);
            primaryImage.source = "";
            primaryImage.source = targetSource;
            primaryImage.opacity = 1.0;
            secondaryImage.source = "";
            secondaryImage.opacity = 0.0;
            root.currentImagePath = targetSource;
        } else if (targetSource !== root.currentImagePath) {
            console.log("[9to5-wallpaper] Crossfading to new image:", targetSource);
            secondaryImage.source = targetSource;
            opacityAnimator.restart();
        }
    }

    function checkClockSync() {
        if (!root.sortedSlots || root.sortedSlots.length === 0) {
            return;
        }

        var slots = root.sortedSlots;

        var now = new Date();
        var currentMins = now.getHours() * 60 + now.getMinutes();

        var activeIdx = -1;
        for (var i = 0; i < slots.length; i++) {
            if (root.timeToMinutes(slots[i].time) <= currentMins) {
                activeIdx = i;
            } else {
                break;
            }
        }
        if (activeIdx === -1) {
            activeIdx = slots.length - 1;
        }

        var expectedSlot = slots[activeIdx];
        if (root.currentSlot && root.currentSlot.time !== expectedSlot.time) {
            console.log("[9to5-wallpaper] Clock drift or wake detected. Resyncing slot to:", expectedSlot.time);
            root.updateScheduledSlot(true);
        }
    }

    // Reactive Watchers
    Connections {
        target: root.configuration
        ignoreUnknownSignals: true
        function onValueChanged(key, value) {
            console.log("[9to5-wallpaper] Plasma configuration onValueChanged signal:", key, "=", value);
            if (key === "ActiveProfile" || key === "ProfileRevision") {
                root.reloadProfile();
            } else if (key === "FillMode" || key === "EnableTransitions" || key === "TransitionDuration" || key === "FallbackColor") {
                root.updateScheduledSlot(false);
            }
        }
    }

    Component.onCompleted: {
        root.reloadProfile();
    }
}
