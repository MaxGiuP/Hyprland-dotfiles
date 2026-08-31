import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentSection {
    function setGtkDraft(values) {
        gnomeThemeCombo.combo.currentIndex = values.themeIndex
        gnomeIconCombo.combo.currentIndex = values.iconIndex
        gnomeCursorCombo.combo.currentIndex = values.cursorIndex
        gnomeFontFamilyCombo.combo.currentIndex = values.fontFamilyIndex
        gnomeFontSizeSpin.value = values.fontSize
        gnomeFontSizePresetCombo.combo.currentIndex = values.fontSizePresetIndex
        gnomeWeightCombo.combo.currentIndex = values.weightIndex
    }

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


        icon: "deployed_code"
        title: Translation.tr("GNOME interface settings")

        ConfigRow {
uniform: true
DesktopThemeLabeledCombo {
    id: gnomeThemeCombo
    label: Translation.tr("GTK theme")
    options: DesktopThemeSettings.gtkThemeOptions
    currentValue: DesktopThemeSettings.gnomeGtkTheme
}
DesktopThemeLabeledCombo {
    id: gnomeIconCombo
    label: Translation.tr("Icon theme")
    options: DesktopThemeSettings.iconThemeOptions
    currentValue: DesktopThemeSettings.gnomeIconTheme
}
        }

        ConfigRow {
uniform: true
DesktopThemeLabeledCombo {
    id: gnomeCursorCombo
    label: Translation.tr("Cursor theme")
    options: DesktopThemeSettings.cursorThemeOptions
    currentValue: DesktopThemeSettings.gnomeCursorTheme
}
DesktopThemeLabeledCombo {
    id: gnomeFontFamilyCombo
    label: Translation.tr("Font family")
    options: DesktopThemeSettings.fontFamilyOptions
    currentValue: DesktopThemeSettings.parseGtkFontFamily(DesktopThemeSettings.gnomeFont)
}
        }

        StyledText {
color: Appearance.colors.colSubtext
font.pixelSize: Appearance.font.pixelSize.small
text: Translation.tr("Color scheme")
        }

        StyledComboBox {
id: gnomeColorCombo
textRole: "displayName"
model: [
    { displayName: Translation.tr("Default"), value: "default", icon: "contrast" },
    { displayName: Translation.tr("Prefer dark"), value: "prefer-dark", icon: "dark_mode" },
    { displayName: Translation.tr("Prefer light"), value: "prefer-light", icon: "light_mode" }
]
currentIndex: Math.max(0, model.findIndex(item => item.value === DesktopThemeSettings.gnomeColorScheme))
        }

        ConfigRow {
uniform: true
ConfigSpinBox {
    id: gnomeCursorSizeSpin
    icon: "mouse"
    text: Translation.tr("Cursor size")
    from: 16
    to: 96
    stepSize: 1
    value: DesktopThemeSettings.gnomeCursorSize
}
ConfigSpinBox {
    id: gnomeTextScalingSpin
    icon: "format_size"
    text: Translation.tr("Text scaling (%)")
    from: 50
    to: 200
    stepSize: 5
    value: Math.round(DesktopThemeSettings.gnomeTextScaling * 100)
}
        }

        ConfigRow {
uniform: true
DesktopThemeLabeledCombo {
    id: gnomeFontSizePresetCombo
    label: Translation.tr("Size preset")
    options: DesktopThemeSettings.fontSizeOptions
    currentValue: `${DesktopThemeSettings.parseGtkFontSize(DesktopThemeSettings.gnomeFont)}`
    onValuePicked: value => gnomeFontSizeSpin.value = Number(value || gnomeFontSizeSpin.value)
}
ConfigSpinBox {
    id: gnomeFontSizeSpin
    icon: "text_fields"
    text: Translation.tr("Font size")
    from: 8
    to: 24
    stepSize: 1
    value: DesktopThemeSettings.parseGtkFontSize(DesktopThemeSettings.gnomeFont)
}
DesktopThemeLabeledCombo {
    id: gnomeWeightCombo
    label: Translation.tr("Weight")
    options: DesktopThemeSettings.fontWeightOptions
    currentValue: DesktopThemeSettings.parseGtkFontWeight(DesktopThemeSettings.gnomeFont)
}
        }

        ConfigRow {
uniform: true
ConfigSwitch {
    id: gnomeAnimationsSwitch
    buttonIcon: "animation"
    text: Translation.tr("Animations")
    checked: DesktopThemeSettings.gnomeAnimations
}
ConfigSwitch {
    id: gnomeHotCornersSwitch
    buttonIcon: "crop_free"
    text: Translation.tr("Hot corners")
    checked: DesktopThemeSettings.gnomeHotCorners
}
        }

        ConfigRow {
uniform: true
ConfigSwitch {
    id: gnomeBatteryPercentSwitch
    buttonIcon: "battery_full_alt"
    text: Translation.tr("Show battery percentage")
    checked: DesktopThemeSettings.gnomeShowBatteryPercentage
}
StyledComboBox {
    id: gnomeClockCombo
    textRole: "displayName"
    model: [
        { displayName: Translation.tr("24-hour"), value: "24h", icon: "schedule" },
        { displayName: Translation.tr("12-hour"), value: "12h", icon: "schedule" }
    ]
    currentIndex: Math.max(0, model.findIndex(item => item.value === DesktopThemeSettings.gnomeClockFormat))
}
        }

        RippleButtonWithIcon {
Layout.fillWidth: true
materialIcon: "settings"
mainText: Translation.tr("Apply GNOME interface settings")
onClicked: DesktopThemeSettings.applyGnome({
    gtkTheme: gnomeThemeCombo.combo.model[gnomeThemeCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.gnomeGtkTheme,
    iconTheme: gnomeIconCombo.combo.model[gnomeIconCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.gnomeIconTheme,
    cursorTheme: gnomeCursorCombo.combo.model[gnomeCursorCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.gnomeCursorTheme,
    fontFamily: gnomeFontFamilyCombo.combo.model[gnomeFontFamilyCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.parseGtkFontFamily(DesktopThemeSettings.gnomeFont),
    fontWeight: gnomeWeightCombo.combo.model[gnomeWeightCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.parseGtkFontWeight(DesktopThemeSettings.gnomeFont),
    fontSize: gnomeFontSizeSpin.value,
    colorScheme: gnomeColorCombo.model[gnomeColorCombo.currentIndex]?.value ?? "default",
    cursorSize: gnomeCursorSizeSpin.value,
    textScaling: gnomeTextScalingSpin.value / 100,
    animations: gnomeAnimationsSwitch.checked,
    hotCorners: gnomeHotCornersSwitch.checked,
    showBatteryPercentage: gnomeBatteryPercentSwitch.checked,
    clockFormat: gnomeClockCombo.model[gnomeClockCombo.currentIndex]?.value ?? "24h"
})
        }
}
