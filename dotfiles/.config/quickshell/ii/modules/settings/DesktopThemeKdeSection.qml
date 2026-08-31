import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentSection {
    component DesktopThemeLabeledCombo: ColumnLayout {
        required property string label
        required property var options
        required property string currentValue
        property alias combo: combo
        property var onValuePicked: null
        Layout.fillWidth: true
        spacing: 4

        StyledText {
            text: parent.label
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledComboBox {
            id: combo
            Layout.fillWidth: true
            textRole: "displayName"
            model: parent.options
            currentIndex: Math.max(0, model.findIndex(item => item.value === parent.currentValue))
            onActivated: index => {
                if (parent.onValuePicked)
                    parent.onValuePicked(model[index]?.value)
            }
        }
    }


        icon: "widgets"
        title: Translation.tr("KDE / Qt theme files")

        ConfigRow {
uniform: true
DesktopThemeLabeledCombo {
    id: kdeColorCombo
    label: Translation.tr("Color scheme")
    options: DesktopThemeSettings.kdeColorSchemeOptions
    currentValue: DesktopThemeSettings.kdeColorScheme
}
DesktopThemeLabeledCombo {
    id: kdeIconCombo
    label: Translation.tr("Icon theme")
    options: DesktopThemeSettings.iconThemeOptions
    currentValue: DesktopThemeSettings.kdeIconTheme
}
        }

        ConfigRow {
uniform: true
DesktopThemeLabeledCombo {
    id: kdeLookCombo
    label: Translation.tr("Look and feel package")
    options: DesktopThemeSettings.kdeLookAndFeelOptions
    currentValue: DesktopThemeSettings.kdeLookAndFeel
}
DesktopThemeLabeledCombo {
    id: kdeFontFamilyCombo
    label: Translation.tr("Font family")
    options: DesktopThemeSettings.fontFamilyOptions
    currentValue: DesktopThemeSettings.parseKdeFontFamily(DesktopThemeSettings.kdeFont)
}
        }

        ConfigRow {
uniform: true
DesktopThemeLabeledCombo {
    id: kvantumCombo
    label: Translation.tr("Kvantum theme")
    options: DesktopThemeSettings.kvantumThemeOptions
    currentValue: DesktopThemeSettings.kvantumTheme
}
ConfigSwitch {
    id: kdeAutoLookSwitch
    buttonIcon: "auto_mode"
    text: Translation.tr("Automatic look and feel")
    checked: DesktopThemeSettings.kdeAutomaticLookAndFeel
}
        }

        ConfigSwitch {
id: kdeDeleteSwitch
buttonIcon: "delete"
text: Translation.tr("Show Delete command")
checked: DesktopThemeSettings.kdeShowDeleteCommand
        }

        ConfigRow {
uniform: true
DesktopThemeLabeledCombo {
    id: kdeFontSizePresetCombo
    label: Translation.tr("Size preset")
    options: DesktopThemeSettings.fontSizeOptions
    currentValue: `${DesktopThemeSettings.parseKdeFontSize(DesktopThemeSettings.kdeFont)}`
    onValuePicked: value => kdeFontSizeSpin.value = Number(value || kdeFontSizeSpin.value)
}
ConfigSpinBox {
    id: kdeFontSizeSpin
    icon: "format_size"
    text: Translation.tr("Font size")
    from: 8
    to: 24
    stepSize: 1
    value: DesktopThemeSettings.parseKdeFontSize(DesktopThemeSettings.kdeFont)
}
DesktopThemeLabeledCombo {
    id: kdeWeightCombo
    label: Translation.tr("Weight")
    options: DesktopThemeSettings.fontWeightOptions
    currentValue: DesktopThemeSettings.parseKdeFontWeight(DesktopThemeSettings.kdeFont)
}
        }

        ConfigRow {
uniform: true
RippleButtonWithIcon {
    Layout.fillWidth: true
    materialIcon: "save"
    mainText: Translation.tr("Save kdeglobals")
    onClicked: DesktopThemeSettings.saveKde({
        colorScheme: kdeColorCombo.combo.model[kdeColorCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.kdeColorScheme,
        iconTheme: kdeIconCombo.combo.model[kdeIconCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.kdeIconTheme,
        lookAndFeel: kdeLookCombo.combo.model[kdeLookCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.kdeLookAndFeel,
        fontFamily: kdeFontFamilyCombo.combo.model[kdeFontFamilyCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.parseKdeFontFamily(DesktopThemeSettings.kdeFont),
        fontWeight: kdeWeightCombo.combo.model[kdeWeightCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.parseKdeFontWeight(DesktopThemeSettings.kdeFont),
        fontSize: kdeFontSizeSpin.value
    })
}

RippleButtonWithIcon {
    Layout.fillWidth: true
    materialIcon: "save"
    mainText: Translation.tr("Save Kvantum theme")
    onClicked: DesktopThemeSettings.saveKvantumTheme(kvantumCombo.combo.model[kvantumCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.kvantumTheme)
}
        }

        RippleButtonWithIcon {
Layout.fillWidth: true
materialIcon: "tune"
mainText: Translation.tr("Save KDE behavior toggles")
onClicked: DesktopThemeSettings.saveKdeToggles({
    automaticLookAndFeel: kdeAutoLookSwitch.checked,
    showDeleteCommand: kdeDeleteSwitch.checked
})
        }
}
