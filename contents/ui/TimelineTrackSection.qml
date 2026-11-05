import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: trackRoot
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    property var slotsModel: null
    property string bootWallpaperPath: ""

    signal addImagesRequested()
    signal addBlankSlotRequested()
    signal distributeEvenlyRequested()
    signal presetSelected(string preset)
    signal slotTimeEdited(int idx, string newTime)
    signal slotLabelEdited(int idx, string newLabel)
    signal imageAssigned(int idx, string imagePath, string thumbPath)
    signal pickImageRequested(int idx)
    signal moveLeftRequested(int idx)
    signal moveRightRequested(int idx)
    signal removeRequested(int idx)
    signal setAsBootWallpaperRequested(int idx, string imagePath)

    function i18nText(text) {
        return (typeof i18nd !== "undefined") ? i18nd("plasma_wallpaper_org.kde.plasma.9to5", text)
             : (typeof i18n !== "undefined") ? i18n(text) : text;
    }

    QQC2.Label {
        text: trackRoot.i18nText("Timeline")
        font.bold: true
        font.pointSize: 11
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
    }

    Flow {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            icon.name: "insert-image"
            text: trackRoot.i18nText("Add Images")
            onClicked: trackRoot.addImagesRequested()
        }

        QQC2.Button {
            icon.name: "list-add"
            text: trackRoot.i18nText("Add Blank Slot")
            onClicked: trackRoot.addBlankSlotRequested()
        }

        QQC2.Button {
            icon.name: "view-grid"
            text: trackRoot.i18nText("Distribute Evenly")
            enabled: trackRoot.slotsModel && trackRoot.slotsModel.count > 1
            onClicked: trackRoot.distributeEvenlyRequested()
        }

        QQC2.ComboBox {
            id: presetsComboBox
            model: [
                { text: trackRoot.i18nText("Apply a preset"), value: "none" },
                { text: trackRoot.i18nText("2-Stage (Day / Night)"), value: "2stage" },
                { text: trackRoot.i18nText("4-Stage (Dawn / Noon / Dusk / Night)"), value: "4stage" },
                { text: trackRoot.i18nText("8-Stage (3-hour intervals)"), value: "8stage" },
                { text: trackRoot.i18nText("16-Stage (90-minute intervals)"), value: "16stage" }
            ]
            textRole: "text"
            valueRole: "value"

            onActivated: {
                if (currentValue !== "none") {
                    trackRoot.presetSelected(currentValue);
                    presetsComboBox.currentIndex = 0;
                }
            }
        }
    }

    // Horizontal Scrollable Unified Timeline
    ListView {
        id: timelineListView
        objectName: "timelineListView"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        implicitHeight: Kirigami.Units.gridUnit * 17
        orientation: ListView.Horizontal
        spacing: Kirigami.Units.largeSpacing
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        model: trackRoot.slotsModel

        delegate: SlotCard {
            required property int index
            required property var model

            slotIndex: index
            totalSlots: trackRoot.slotsModel ? trackRoot.slotsModel.count : 0
            time: model.time
            label: model.label || ""
            imagePath: model.imagePath || ""
            thumbPath: model.thumbPath || ""
            isBootWallpaper: (trackRoot.bootWallpaperPath.length > 0 && model.imagePath && trackRoot.bootWallpaperPath === model.imagePath.replace("file://", ""))

            onSlotTimeEdited: (idx, newTime) => trackRoot.slotTimeEdited(idx, newTime)
            onSlotLabelEdited: (idx, newLabel) => trackRoot.slotLabelEdited(idx, newLabel)
            onImageAssigned: (idx, newImg, newThumb) => trackRoot.imageAssigned(idx, newImg, newThumb)
            onPickImageRequested: (idx) => trackRoot.pickImageRequested(idx)
            onMoveLeftRequested: (idx) => trackRoot.moveLeftRequested(idx)
            onMoveRightRequested: (idx) => trackRoot.moveRightRequested(idx)
            onRemoveRequested: (idx) => trackRoot.removeRequested(idx)
            onSetAsBootWallpaperRequested: (idx, img) => trackRoot.setAsBootWallpaperRequested(idx, img)
        }

        footer: Item {
            width: Kirigami.Units.gridUnit * 7.5 + Kirigami.Units.largeSpacing
            height: timelineListView.height

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.top: parent.top
                width: Kirigami.Units.gridUnit * 7.5
                height: Kirigami.Units.gridUnit * 14
                color: Kirigami.Theme.alternateBackgroundColor
                border.color: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.15)
                radius: Kirigami.Units.cornerRadius

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.ToolButton {
                        Layout.alignment: Qt.AlignHCenter
                        icon.name: "list-add"
                        onClicked: trackRoot.addBlankSlotRequested()
                    }

                    QQC2.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: trackRoot.i18nText("Add Slot")
                        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.65)
                        opacity: 0.7
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: trackRoot.addBlankSlotRequested()
                }
            }
        }

        WheelHandler {
            target: timelineListView
            property: "contentX"
            orientation: Qt.Vertical
            rotationScale: Kirigami.Units.gridUnit * 4
        }

        QQC2.ScrollBar.horizontal: QQC2.ScrollBar {
            policy: timelineListView.contentWidth > timelineListView.width ? QQC2.ScrollBar.AlwaysOn : QQC2.ScrollBar.AsNeeded
        }
    }
}
