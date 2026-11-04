import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property int slotIndex: 0
    property int totalSlots: 1
    property string time: "12:00"
    property string label: ""
    property string imagePath: ""
    property string thumbPath: ""

    signal removeRequested(int index)
    signal moveLeftRequested(int index)
    signal moveRightRequested(int index)
    signal slotTimeEdited(int index, string newTime)
    signal slotLabelEdited(int index, string newLabel)
    signal imageAssigned(int index, string newImagePath, string newThumbPath)
    signal pickImageRequested(int index)

    function i18nText(text) {
        if (typeof i18nd !== "undefined") {
            return i18nd("plasma_wallpaper_org.kde.plasma.9to5", text);
        }
        if (typeof i18n !== "undefined") {
            return i18n(text);
        }
        return text;
    }

    // Parse time into hours and minutes
    readonly property int currentHour: {
        var p = (root.time || "12:00").split(":");
        return parseInt(p[0], 10) || 0;
    }
    readonly property int currentMinute: {
        var p = (root.time || "12:00").split(":");
        return parseInt(p[1], 10) || 0;
    }

    implicitWidth: Kirigami.Units.gridUnit * 10
    implicitHeight: Kirigami.Units.gridUnit * 14

    color: dropArea.containsDrag ? Kirigami.Theme.alternateBackgroundColor : Kirigami.Theme.backgroundColor
    border.color: dropArea.containsDrag ? Kirigami.Theme.focusColor : Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.15)
    border.width: dropArea.containsDrag ? 2 : 1
    radius: Kirigami.Units.cornerRadius

    DropArea {
        id: dropArea
        anchors.fill: parent

        onDropped: (drop) => {
            if (drop.hasUrls && drop.urls.length > 0) {
                var rawStr = drop.urls[0].toString();
                if (rawStr.indexOf("file://") === 0) {
                    rawStr = rawStr.substring(7);
                }
                var cleanPath = decodeURIComponent(rawStr);
                root.imageAssigned(root.slotIndex, cleanPath, cleanPath);
                drop.accept();
            } else if (drop.source && drop.source.imagePath) {
                root.imageAssigned(root.slotIndex, drop.source.imagePath, drop.source.thumbPath || drop.source.imagePath);
                drop.accept();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // Top Toolbar: Move Left / Slot Number / Move Right / Delete
        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            QQC2.ToolButton {
                icon.name: "go-previous"
                display: QQC2.AbstractButton.IconOnly
                enabled: root.slotIndex > 0
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: root.i18nText("Move earlier")
                onClicked: root.moveLeftRequested(root.slotIndex)
            }

            QQC2.Label {
                text: "#" + (root.slotIndex + 1)
                font.bold: true
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.7
            }

            QQC2.ToolButton {
                icon.name: "go-next"
                display: QQC2.AbstractButton.IconOnly
                enabled: root.slotIndex < root.totalSlots - 1
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: root.i18nText("Move later")
                onClicked: root.moveRightRequested(root.slotIndex)
            }

            QQC2.ToolButton {
                icon.name: "edit-delete-remove"
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: root.i18nText("Remove slot")
                onClicked: root.removeRequested(root.slotIndex)
            }
        }

        // Preview thumbnail / Image Drop Target
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Kirigami.Theme.alternateBackgroundColor
            border.color: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.1)
            radius: Kirigami.Units.cornerRadius
            clip: true

            Image {
                id: previewImage
                anchors.fill: parent
                source: root.thumbPath ? ("file://" + root.thumbPath) : (root.imagePath ? ("file://" + root.imagePath) : "")
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: previewImage.status !== Image.Ready
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: Kirigami.Units.iconSizes.large
                    implicitHeight: Kirigami.Units.iconSizes.large
                    source: "insert-image"
                    opacity: 0.6
                }

                QQC2.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.i18nText("Choose Image")
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    opacity: 0.6
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pickImageRequested(root.slotIndex)
            }
        }

        // Time Picker: Dual SpinBoxes (Hours : Minutes)
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 2

            QQC2.SpinBox {
                id: hoursSpin
                from: 0
                to: 23
                value: root.currentHour
                editable: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3.8

                textFromValue: function(value) {
                    return (value < 10 ? "0" : "") + value;
                }
                valueFromText: function(text) {
                    return parseInt(text, 10) || 0;
                }

                onValueModified: {
                    var hh = (value < 10 ? "0" : "") + value;
                    var mm = (minutesSpin.value < 10 ? "0" : "") + minutesSpin.value;
                    root.slotTimeEdited(root.slotIndex, hh + ":" + mm);
                }
            }

            QQC2.Label {
                text: ":"
                font.bold: true
            }

            QQC2.SpinBox {
                id: minutesSpin
                from: 0
                to: 59
                stepSize: 5
                value: root.currentMinute
                editable: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3.8

                textFromValue: function(value) {
                    return (value < 10 ? "0" : "") + value;
                }
                valueFromText: function(text) {
                    return parseInt(text, 10) || 0;
                }

                onValueModified: {
                    var hh = (hoursSpin.value < 10 ? "0" : "") + hoursSpin.value;
                    var mm = (value < 10 ? "0" : "") + value;
                    root.slotTimeEdited(root.slotIndex, hh + ":" + mm);
                }
            }
        }

        // Slot Label
        QQC2.TextField {
            id: labelField
            Layout.fillWidth: true
            text: root.label
            placeholderText: root.i18nText("Label (optional)")
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize

            onEditingFinished: {
                if (text !== root.label) {
                    root.slotLabelEdited(root.slotIndex, text.trim());
                }
            }
        }
    }
}
