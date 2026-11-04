import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as QtDialogs
import org.kde.kirigami as Kirigami
import "ProfileLogic.js" as ProfileLogic

Item {
    id: dialogsRoot

    property int targetSlotForSinglePicker: -1
    property string activeExportProfileId: ""

    signal profileCreateAccepted(string name)
    signal bulkImagesAccepted(var paths)
    signal singleImageAccepted(int slotIndex, string path)
    signal heicImportAccepted(string path)
    signal heicExportAccepted(string profileId, string targetPath)

    function i18nText(text) {
        return (typeof i18nd !== "undefined") ? i18nd("plasma_wallpaper_org.kde.plasma.9to5", text)
             : (typeof i18n !== "undefined") ? i18n(text) : text;
    }

    function openNewProfileDialog() {
        newProfileNameField.text = "";
        newProfileDialog.open();
    }

    function openBulkImagesDialog() {
        bulkImagesDialog.open();
    }

    function openSingleImageDialog(slotIndex) {
        targetSlotForSinglePicker = slotIndex;
        singleImageDialog.open();
    }

    function openHeicImportDialog() {
        heicImportDialog.open();
    }

    function openHeicExportDialog(profileId) {
        activeExportProfileId = profileId;
        heicExportDialog.open();
    }

    // 1. New Profile Dialog
    QQC2.Dialog {
        id: newProfileDialog
        title: dialogsRoot.i18nText("Create New Profile")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        x: Math.round((parent ? (parent.width - width) / 2 : 100))
        y: Math.round((parent ? (parent.height - height) / 2 : 100))
        modal: true

        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            QQC2.Label {
                text: dialogsRoot.i18nText("Profile Name:")
            }

            QQC2.TextField {
                id: newProfileNameField
                placeholderText: dialogsRoot.i18nText("My Dynamic Wallpaper")
                Layout.fillWidth: true
            }
        }

        onAccepted: {
            var name = newProfileNameField.text.trim();
            if (name.length > 0) {
                dialogsRoot.profileCreateAccepted(name);
                newProfileNameField.text = "";
            }
        }
    }

    // 2. Bulk Add Images Dialog
    QtDialogs.FileDialog {
        id: bulkImagesDialog
        title: dialogsRoot.i18nText("Select Images to Add to Timeline")
        fileMode: QtDialogs.FileDialog.OpenFiles
        nameFilters: [
            dialogsRoot.i18nText("Image Files (*.jpg *.jpeg *.png *.webp *.avif *.heic)"),
            dialogsRoot.i18nText("All Files (*)")
        ]

        onAccepted: {
            if (selectedFiles && selectedFiles.length > 0) {
                var cleanPaths = [];
                for (var i = 0; i < selectedFiles.length; i++) {
                    cleanPaths.push(ProfileLogic.urlToPath(selectedFiles[i]));
                }
                dialogsRoot.bulkImagesAccepted(cleanPaths);
            }
        }
    }

    // 3. Single Image Picker Dialog
    QtDialogs.FileDialog {
        id: singleImageDialog
        title: dialogsRoot.i18nText("Select Wallpaper Image for Slot")
        fileMode: QtDialogs.FileDialog.OpenFile
        nameFilters: [
            dialogsRoot.i18nText("Image Files (*.jpg *.jpeg *.png *.webp *.avif *.heic)"),
            dialogsRoot.i18nText("All Files (*)")
        ]

        onAccepted: {
            if (selectedFile && dialogsRoot.targetSlotForSinglePicker >= 0) {
                var cleanPath = ProfileLogic.urlToPath(selectedFile);
                var slotIdx = dialogsRoot.targetSlotForSinglePicker;
                dialogsRoot.targetSlotForSinglePicker = -1;
                dialogsRoot.singleImageAccepted(slotIdx, cleanPath);
            }
        }
    }

    // 4. HEIC Import Dialog
    QtDialogs.FileDialog {
        id: heicImportDialog
        title: dialogsRoot.i18nText("Select Apple Dynamic .heic Wallpaper")
        fileMode: QtDialogs.FileDialog.OpenFile
        nameFilters: [
            dialogsRoot.i18nText("Apple Dynamic Wallpaper (*.heic *.HEIC)"),
            dialogsRoot.i18nText("All Files (*)")
        ]

        onAccepted: {
            if (selectedFile) {
                var cleanPath = ProfileLogic.urlToPath(selectedFile);
                dialogsRoot.heicImportAccepted(cleanPath);
            }
        }
    }

    // 5. HEIC Export Dialog
    QtDialogs.FileDialog {
        id: heicExportDialog
        title: dialogsRoot.i18nText("Export Dynamic Wallpaper to .heic")
        fileMode: QtDialogs.FileDialog.SaveFile
        nameFilters: [
            dialogsRoot.i18nText("Apple Dynamic Wallpaper (*.heic)"),
            dialogsRoot.i18nText("All Files (*)")
        ]

        onAccepted: {
            if (selectedFile) {
                var targetPath = ProfileLogic.urlToPath(selectedFile);
                if (!targetPath.toLowerCase().endsWith(".heic")) {
                    targetPath += ".heic";
                }
                dialogsRoot.heicExportAccepted(dialogsRoot.activeExportProfileId, targetPath);
            }
        }
    }
}
