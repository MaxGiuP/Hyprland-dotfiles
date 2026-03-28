import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true
    baseWidth: 760

    ContentSection {
        icon: "accessibility_new"
        title: Translation.tr("Accessibility")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("These controls focus on readability and motion. They are backed by the GNOME interface settings already exposed in the theme stack.")
        }
    }

    ContentSection {
        icon: "text_fields"
        title: Translation.tr("Readability")

        ConfigRow {
            uniform: true

            ConfigSpinBox {
                id: cursorSizeSpin
                icon: "mouse"
                text: Translation.tr("Cursor size")
                from: 16
                to: 96
                stepSize: 1
                value: DesktopThemeSettings.gnomeCursorSize
            }

            ConfigSpinBox {
                id: textScalingSpin
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

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "save"
                mainText: Translation.tr("Apply accessibility sizing")
                onClicked: DesktopThemeSettings.applyGnome({
                    gtkTheme: DesktopThemeSettings.gnomeGtkTheme,
                    iconTheme: DesktopThemeSettings.gnomeIconTheme,
                    cursorTheme: DesktopThemeSettings.gnomeCursorTheme,
                    fontFamily: DesktopThemeSettings.parseGtkFontFamily(DesktopThemeSettings.gnomeFont),
                    fontWeight: DesktopThemeSettings.parseGtkFontWeight(DesktopThemeSettings.gnomeFont),
                    fontSize: DesktopThemeSettings.parseGtkFontSize(DesktopThemeSettings.gnomeFont),
                    colorScheme: DesktopThemeSettings.gnomeColorScheme || "default",
                    cursorSize: cursorSizeSpin.value,
                    textScaling: textScalingSpin.value / 100,
                    animations: DesktopThemeSettings.gnomeAnimations,
                    hotCorners: DesktopThemeSettings.gnomeHotCorners,
                    showBatteryPercentage: DesktopThemeSettings.gnomeShowBatteryPercentage,
                    clockFormat: DesktopThemeSettings.gnomeClockFormat
                })
            }
        }
    }

    ContentSection {
        icon: "animation"
        title: Translation.tr("Motion")

        ConfigSwitch {
            id: animationsSwitch
            buttonIcon: "animation"
            text: Translation.tr("Enable animations")
            checked: DesktopThemeSettings.gnomeAnimations
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "save"
            mainText: Translation.tr("Apply motion preference")
            onClicked: DesktopThemeSettings.applyGnome({
                gtkTheme: DesktopThemeSettings.gnomeGtkTheme,
                iconTheme: DesktopThemeSettings.gnomeIconTheme,
                cursorTheme: DesktopThemeSettings.gnomeCursorTheme,
                fontFamily: DesktopThemeSettings.parseGtkFontFamily(DesktopThemeSettings.gnomeFont),
                fontWeight: DesktopThemeSettings.parseGtkFontWeight(DesktopThemeSettings.gnomeFont),
                fontSize: DesktopThemeSettings.parseGtkFontSize(DesktopThemeSettings.gnomeFont),
                colorScheme: DesktopThemeSettings.gnomeColorScheme || "default",
                cursorSize: DesktopThemeSettings.gnomeCursorSize,
                textScaling: DesktopThemeSettings.gnomeTextScaling,
                animations: animationsSwitch.checked,
                hotCorners: DesktopThemeSettings.gnomeHotCorners,
                showBatteryPercentage: DesktopThemeSettings.gnomeShowBatteryPercentage,
                clockFormat: DesktopThemeSettings.gnomeClockFormat
            })
        }
    }
}
