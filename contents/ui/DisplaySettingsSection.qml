import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

Kirigami.FormLayout {
    id: optionsForm
    Layout.fillWidth: true

    property var parentLayout: null
    property var twinLayout: null
    property bool isWideMode: parentLayout ? parentLayout.wideMode : (width >= Kirigami.Units.gridUnit * 30)
    wideMode: isWideMode

    property alias enableTransitions: enableTransitionsSwitch.checked
    property alias transitionDuration: transitionSlider.value
    property alias fallbackColor: fallbackColorButton.color
    property alias dynamicAccentColor: dynamicAccentSwitch.checked

    property int cfgFillMode: Image.PreserveAspectCrop
    signal fillModeSelected(int mode)

    function i18nText(text) {
        return (typeof i18nd !== "undefined") ? i18nd("plasma_wallpaper_org.kde.plasma.9to5", text)
             : (typeof i18n !== "undefined") ? i18n(text) : text;
    }

    onCfgFillModeChanged: {
        var idx = fillModeComboBox.indexOfValue(cfgFillMode);
        if (idx >= 0) {
            fillModeComboBox.currentIndex = idx;
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
        var idx = fillModeComboBox.indexOfValue(cfgFillMode);
        if (idx >= 0) fillModeComboBox.currentIndex = idx;
    }

    QQC2.CheckBox {
        id: enableTransitionsSwitch
        Kirigami.FormData.label: optionsForm.i18nText("Transitions:")
        text: optionsForm.i18nText("Enable smooth crossfade transitions between time slots")
        checked: true
    }

    RowLayout {
        Kirigami.FormData.label: optionsForm.i18nText("Transition speed:")
        Layout.fillWidth: true
        enabled: enableTransitionsSwitch.checked
        spacing: Kirigami.Units.smallSpacing

        QQC2.Slider {
            id: transitionSlider
            from: 200
            to: 5000
            stepSize: 100
            value: 1500
            Layout.fillWidth: true
        }

        QQC2.Label {
            text: (transitionSlider.value / 1000.0).toFixed(1) + "s"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
        }
    }

    QQC2.ComboBox {
        id: fillModeComboBox
        Kirigami.FormData.label: optionsForm.i18nText("Positioning:")
        Layout.fillWidth: !optionsForm.wideMode
        textRole: "label"
        valueRole: "fillMode"
        model: [
            { label: optionsForm.i18nText("Scaled and cropped (Fill Screen)"), fillMode: Image.PreserveAspectCrop },
            { label: optionsForm.i18nText("Scaled, keep proportions (Fit to Screen)"), fillMode: Image.PreserveAspectFit },
            { label: optionsForm.i18nText("Scaled (Stretch)"), fillMode: Image.Stretch },
            { label: optionsForm.i18nText("Centered (No scaling)"), fillMode: Image.Pad }
        ]
        onActivated: optionsForm.fillModeSelected(currentValue)
    }

    QQC2.CheckBox {
        id: dynamicAccentSwitch
        Kirigami.FormData.label: optionsForm.i18nText("Accent color:")
        text: optionsForm.i18nText("Dynamically update Plasma system accent color based on active time of day")
        checked: true
    }

    KQuickControls.ColorButton {
        id: fallbackColorButton
        Kirigami.FormData.label: optionsForm.i18nText("Fallback color:")
        dialogTitle: optionsForm.i18nText("Select Fallback Background Color")
    }
}
