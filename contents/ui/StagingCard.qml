import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property string imagePath: ""
    property string thumbPath: ""
    property string fileName: ""

    signal removeRequested(string path)

    implicitWidth: Kirigami.Units.gridUnit * 7
    implicitHeight: Kirigami.Units.gridUnit * 5

    color: Kirigami.Theme.backgroundColor
    border.color: mouseArea.drag.active ? Kirigami.Theme.focusColor : Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.15)
    border.width: mouseArea.drag.active ? 2 : 1
    radius: Kirigami.Units.cornerRadius
    clip: true

    Drag.active: mouseArea.drag.active
    Drag.source: root
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2

    Image {
        id: imgPreview
        anchors.fill: parent
        source: root.thumbPath ? ("file://" + root.thumbPath) : (root.imagePath ? ("file://" + root.imagePath) : "")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium
        source: "image-x-generic"
        visible: imgPreview.status !== Image.Ready
        opacity: 0.5
    }

    // Semi-transparent label bar at bottom
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Kirigami.Units.gridUnit * 1.2
        color: Kirigami.Theme.backgroundColor
        opacity: 0.85

        QQC2.Label {
            anchors.fill: parent
            anchors.margins: 2
            text: root.fileName || root.imagePath.split("/").pop()
            elide: Text.ElideMiddle
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Remove button
    QQC2.ToolButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 2
        icon.name: "edit-delete-remove"
        display: QQC2.AbstractButton.IconOnly
        width: Kirigami.Units.iconSizes.small * 1.5
        height: width
        visible: mouseArea.containsMouse
        onClicked: root.removeRequested(root.imagePath)
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        drag.target: root

        onReleased: {
            root.Drag.drop();
            // Reset position back to layout slot if not dropped on target
            root.x = 0;
            root.y = 0;
        }
    }
}
