

// Convert QML file:// URL to clean filesystem path
function urlToPath(url) {
    if (!url) return "";
    var str = url.toString();
    if (str.indexOf("file://") === 0) {
        str = str.substring(7);
    }
    return decodeURIComponent(str);
}

// Convert "HH:mm" time string to minutes from midnight
function parseTimeToMinutes(t) {
    var p = (t || "12:00").split(":");
    return (parseInt(p[0], 10) || 0) * 60 + (parseInt(p[1], 10) || 0);
}

// Format minutes from midnight to "HH:mm" string
function formatMinutesToTime(totalMins) {
    var m = Math.round(totalMins) % 1440;
    if (m < 0) m += 1440;
    var hh = Math.floor(m / 60);
    var mm = m % 60;
    return (hh < 10 ? "0" + hh : "" + hh) + ":" + (mm < 10 ? "0" + mm : "" + mm);
}

// Compute evenly distributed "HH:mm" times across a 24-hour cycle
function computeEvenIntervals(count) {
    var result = [];
    if (count <= 0) return result;
    for (var i = 0; i < count; i++) {
        var totalMins = Math.round((i / count) * 1440) % 1440;
        result.push(formatMinutesToTime(totalMins));
    }
    return result;
}

// Returns preset slot arrays: [{ time, label }]
function getPresetSlots(presetType) {
    var times = [];
    if (presetType === "2stage") {
        times = [
            { time: "07:00", label: "Day" },
            { time: "19:00", label: "Night" }
        ];
    } else if (presetType === "4stage") {
        times = [
            { time: "06:00", label: "Dawn" },
            { time: "12:00", label: "Noon" },
            { time: "18:00", label: "Dusk" },
            { time: "22:00", label: "Night" }
        ];
    } else if (presetType === "8stage") {
        for (var h = 0; h < 24; h += 3) {
            times.push({
                time: (h < 10 ? "0" + h : "" + h) + ":00",
                label: ""
            });
        }
    } else if (presetType === "16stage") {
        for (var i = 0; i < 16; i++) {
            times.push({
                time: formatMinutesToTime((i / 16.0) * 1440),
                label: ""
            });
        }
    }
    return times;
}

// Sorts an array of slot objects chronologically by time
function sortSlots(slotsArray) {
    return slotsArray.slice().sort(function(a, b) {
        return parseTimeToMinutes(a.time) - parseTimeToMinutes(b.time);
    });
}

// Generates a sanitized profile ID from a name
function sanitizeProfileId(name) {
    var id = (name || "").toLowerCase().replace(/[^a-z0-9]/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");
    return id || "custom-profile";
}
