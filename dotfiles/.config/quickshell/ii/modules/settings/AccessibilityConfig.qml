import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760
    property int currentSubTab: 0
    property var settingsHost: null

    readonly property var tabs: [
        { name: Translation.tr("Vision"), icon: "visibility" },
        { name: Translation.tr("Motion"), icon: "animation" },
        { name: Translation.tr("Hearing & input"), icon: "hearing" }
    ]

    function applySubTab(subTab, sectionId = "") {
        root.currentSubTab = Math.max(0, Math.min(subTab, root.tabs.length - 1))
        root.contentY = 0
    }

    function navigate(page, subTab = -1, sectionId = "") {
        if (root.settingsHost && typeof root.settingsHost.applyNavigation === "function")
            root.settingsHost.applyNavigation(typeof page === "string" ? SettingsCatalog.indexOf(page) : page, subTab, sectionId)
    }

    SecondaryTabBar {
        Layout.fillWidth: true
        currentIndex: root.currentSubTab
        onCurrentIndexChanged: {
            root.currentSubTab = currentIndex
            root.contentY = 0
        }

        Repeater {
            model: root.tabs
            delegate: SecondaryTabButton {
                required property var modelData
                buttonIcon: modelData.icon
                buttonText: modelData.name
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 0
        icon: "text_fields"
        title: Translation.tr("Text and interface")
        description: Translation.tr("Applied immediately across every Quickshell surface")

        ConfigSlider {
            text: Translation.tr("Text scale")
            buttonIcon: "format_size"
            from: 0.75
            to: 2.0
            stepSize: 0.05
            usePercentTooltip: false
            tooltipDecimals: 2
            value: Config.options.accessibility.textScale
            onValueChanged: Config.options.accessibility.textScale = value
        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "contrast"
                text: Translation.tr("Higher contrast")
                checked: Config.options.accessibility.highContrast
                onCheckedChanged: Config.options.accessibility.highContrast = checked
            }

            ConfigSwitch {
                buttonIcon: "opacity"
                text: Translation.tr("Reduce transparency")
                checked: Config.options.accessibility.reduceTransparency
                onCheckedChanged: Config.options.accessibility.reduceTransparency = checked
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: previewText.implicitHeight + 28
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            StyledText {
                id: previewText
                anchors.fill: parent
                anchors.margins: 14
                text: Translation.tr("The quick brown fox jumps over the lazy dog. 1234567890")
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.Wrap
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 0
        icon: "mouse"
        title: Translation.tr("Pointer")
        description: Translation.tr("Native Hyprland cursor settings")

        ConfigSpinBox {
            icon: "mouse"
            text: Translation.tr("Cursor size")
            from: 16
            to: 96
            stepSize: 1
            value: Config.options.accessibility.cursorSize
            onValueChanged: Config.options.accessibility.cursorSize = value
        }

        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("XCursor theme")
            text: Config.options.accessibility.cursorTheme
            onEditingFinished: {
                const nextTheme = text.trim()
                if (nextTheme.length > 0)
                    Config.options.accessibility.cursorTheme = nextTheme
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Cursor changes are sent directly to Hyprland and restored from config.json when the shell starts.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        visible: root.currentSubTab === 1
        icon: "animation"
        title: Translation.tr("Motion and effects")

        ConfigSwitch {
            buttonIcon: "motion_photos_off"
            text: Translation.tr("Reduce motion")
            checked: Config.options.accessibility.reduceMotion
            onCheckedChanged: Config.options.accessibility.reduceMotion = checked
        }

        ConfigSwitch {
            buttonIcon: "zoom_in_map"
            text: Translation.tr("Opening zoom animation")
            enabled: !Config.options.accessibility.reduceMotion
            checked: Config.options.overlay.openingZoomAnimation
            onCheckedChanged: Config.options.overlay.openingZoomAnimation = checked
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Reduce motion collapses the shell animation timings to zero; controls and navigation remain fully functional.")
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        visible: root.currentSubTab === 2
        icon: "hearing"
        title: Translation.tr("Captions and sound cues")

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "battery_charging_full"
                text: Translation.tr("Battery sound cues")
                checked: Config.options.sounds.battery
                onCheckedChanged: Config.options.sounds.battery = checked
            }

            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Timer sound cues")
                checked: Config.options.sounds.pomodoro
                onCheckedChanged: Config.options.sounds.pomodoro = checked
            }
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "subtitles"
                mainText: GlobalStates.liveCaptionsOpen ? Translation.tr("Hide live captions") : Translation.tr("Show live captions")
                onClicked: GlobalStates.liveCaptionsOpen = !GlobalStates.liveCaptionsOpen
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "settings_voice"
                mainText: Translation.tr("Caption settings")
                onClicked: GlobalStates.openOverlayWidget("liveCaptionsSettings")
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 2
        icon: "keyboard"
        title: Translation.tr("Alternative input")

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "keyboard"
                mainText: GlobalStates.oskOpen ? Translation.tr("Hide on-screen keyboard") : Translation.tr("Open on-screen keyboard")
                onClicked: GlobalStates.oskOpen = !GlobalStates.oskOpen
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "keyboard_alt"
                mainText: Translation.tr("Keyboard settings")
                onClicked: root.navigate("peripherals", 2, "keyboard")
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "hearing"
                mainText: Translation.tr("Audio safety")
                onClicked: root.navigate("audio", 2, "protection")
            }
        }
    }
}
