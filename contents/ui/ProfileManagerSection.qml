import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: profileForm
    Layout.fillWidth: true

    property var parentLayout: null
    property var twinLayout: null
    property bool isWideMode: parentLayout ? parentLayout.wideMode : (width >= Kirigami.Units.gridUnit * 30)
    wideMode: isWideMode

    property var profilesModel: null
    property var slotsModel: null
    property bool isBusy: false

    property alias currentProfileId: profileComboBox.currentValue
    property alias currentProfileText: profileComboBox.currentText
    property alias currentProfileIndex: profileComboBox.currentIndex

    signal profileSelected(string profileId)
    signal newProfileRequested()
    signal duplicateProfileRequested()
    signal deleteProfileRequested()
    signal importHeicRequested()
    signal exportHeicRequested()

    function i18nText(text) {
        return (typeof i18nd !== "undefined") ? i18nd("plasma_wallpaper_org.kde.plasma.9to5", text)
             : (typeof i18n !== "undefined") ? i18n(text) : text;
    }

    function selectProfile(profileId) {
        var idx = profileComboBox.indexOfValue(profileId);
        if (idx >= 0) {
            profileComboBox.currentIndex = idx;
        }
    }

    twinFormLayouts: {
        var twins = [];
        if (parentLayout) twins.push(parentLayout);
        if (twinLayout) twins.push(twinLayout);
        return twins;
    }

    Component.onCompleted: {
        if (parentLayout) twinFormLayouts.push(parentLayout);
        if (twinLayout) twinFormLayouts.push(twinLayout);
    }

    ColumnLayout {
        Kirigami.FormData.label: profileForm.i18nText("Profile:")
        Kirigami.FormData.buddyFor: profileComboBox
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: profileComboBox
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 8
                model: profileForm.profilesModel
                textRole: "name"
                valueRole: "id"

                onActivated: {
                    if (currentValue) {
                        profileForm.profileSelected(currentValue);
                    }
                }
            }

            RowLayout {
                visible: profileForm.wideMode
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    icon.name: "document-new"
                    text: profileForm.i18nText("New")
                    onClicked: profileForm.newProfileRequested()
                }

                QQC2.Button {
                    icon.name: "edit-copy"
                    text: profileForm.i18nText("Duplicate")
                    enabled: profileComboBox.currentIndex >= 0
                    onClicked: profileForm.duplicateProfileRequested()
                }

                QQC2.Button {
                    icon.name: "edit-delete"
                    text: profileForm.i18nText("Delete")
                    enabled: profileComboBox.currentIndex >= 0 && profileForm.profilesModel && profileForm.profilesModel.count > 1
                    onClicked: profileForm.deleteProfileRequested()
                }
            }
        }

        RowLayout {
            visible: !profileForm.wideMode
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                Layout.fillWidth: true
                icon.name: "document-new"
                text: profileForm.i18nText("New")
                onClicked: profileForm.newProfileRequested()
            }

            QQC2.Button {
                Layout.fillWidth: true
                icon.name: "edit-copy"
                text: profileForm.i18nText("Duplicate")
                enabled: profileComboBox.currentIndex >= 0
                onClicked: profileForm.duplicateProfileRequested()
            }

            QQC2.Button {
                Layout.fillWidth: true
                icon.name: "edit-delete"
                text: profileForm.i18nText("Delete")
                enabled: profileComboBox.currentIndex >= 0 && profileForm.profilesModel && profileForm.profilesModel.count > 1
                onClicked: profileForm.deleteProfileRequested()
            }
        }
    }

    Flow {
        Kirigami.FormData.label: profileForm.i18nText("Dynamic HEIC:")
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            icon.name: "document-import"
            text: profileForm.i18nText("Import .heic Preset")
            onClicked: profileForm.importHeicRequested()
        }

        QQC2.Button {
            icon.name: "document-export"
            text: profileForm.i18nText("Export Current to .heic")
            enabled: profileForm.slotsModel && profileForm.slotsModel.count > 0
            onClicked: profileForm.exportHeicRequested()
        }

        QQC2.BusyIndicator {
            id: busySpinner
            running: profileForm.isBusy
            visible: running
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth
        }
    }
}
