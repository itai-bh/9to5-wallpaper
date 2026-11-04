import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: cardRoot

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
        return (typeof i18nd !== "undefined") ? i18nd("plasma_wallpaper_org.kde.plasma.9to5", text)
             : (typeof i18n !== "undefined") ? i18n(text) : text;
    }

    // Parse time into hours and minutes
    readonly property int currentHour: {
        var p = (cardRoot.time || "12:00").split(":");
        return parseInt(p[0], 10) || 0;
    }
    readonly property int currentMinute: {
        var p = (cardRoot.time || "12:00").split(":");
        return parseInt(p[1], 10) || 0;
    }

    implicitWidth: Kirigami.Units.gridUnit * 10
    implicitHeight: Kirigami.Units.gridUnit * 14

    clip: true
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
                cardRoot.imageAssigned(cardRoot.slotIndex, cleanPath, cleanPath);
                drop.accept();
            } else if (drop.source && typeof drop.source.imagePath !== "undefined") {
                var srcImg = drop.source.imagePath;
                var srcThumb = drop.source.thumbPath || srcImg;
                cardRoot.imageAssigned(cardRoot.slotIndex, srcImg, srcThumb);
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
                enabled: cardRoot.slotIndex > 0
                Layout.preferredWidth: Kirigami.Units.iconSizes.small * 1.4
                Layout.preferredHeight: Layout.preferredWidth
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: cardRoot.i18nText("Move earlier")
                onClicked: cardRoot.moveLeftRequested(cardRoot.slotIndex)
            }

            QQC2.Label {
                text: "#" + (cardRoot.slotIndex + 1)
                font.bold: true
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.65)
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.7
            }

            QQC2.ToolButton {
                icon.name: "go-next"
                display: QQC2.AbstractButton.IconOnly
                enabled: cardRoot.slotIndex < cardRoot.totalSlots - 1
                Layout.preferredWidth: Kirigami.Units.iconSizes.small * 1.4
                Layout.preferredHeight: Layout.preferredWidth
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: cardRoot.i18nText("Move later")
                onClicked: cardRoot.moveRightRequested(cardRoot.slotIndex)
            }

            Item {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small * 1.4
                Layout.preferredHeight: Layout.preferredWidth

                Kirigami.Icon {
                    id: removeSlotIcon
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.small
                    height: width
                    source: "edit-delete"
                    opacity: removeSlotMouse.pressed ? 0.5 : (removeSlotMouse.containsMouse ? 1.0 : 0.7)
                }

                MouseArea {
                    id: removeSlotMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    QQC2.ToolTip.visible: containsMouse
                    QQC2.ToolTip.text: cardRoot.i18nText("Remove slot")
                    onClicked: cardRoot.removeRequested(cardRoot.slotIndex)
                }
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
                source: cardRoot.thumbPath ? ("file://" + cardRoot.thumbPath) : (cardRoot.imagePath ? ("file://" + cardRoot.imagePath) : "")
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
                    text: cardRoot.i18nText("Choose Image")
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.65)
                    opacity: 0.6
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: cardRoot.pickImageRequested(cardRoot.slotIndex)
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
                value: cardRoot.currentHour
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
                    cardRoot.slotTimeEdited(cardRoot.slotIndex, hh + ":" + mm);
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
                value: cardRoot.currentMinute
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
                    cardRoot.slotTimeEdited(cardRoot.slotIndex, hh + ":" + mm);
                }
            }
        }

        // Slot Label
        QQC2.TextField {
            id: labelField
            Layout.fillWidth: true
            text: cardRoot.label
            placeholderText: cardRoot.i18nText("Label (optional)")
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.65)

            onEditingFinished: {
                if (text !== cardRoot.label) {
                    cardRoot.slotLabelEdited(cardRoot.slotIndex, text.trim());
                }
            }
        }
    }
}
