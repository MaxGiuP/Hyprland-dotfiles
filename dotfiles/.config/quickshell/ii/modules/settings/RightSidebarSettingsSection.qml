import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    icon: "right_panel_open"
    title: Translation.tr("Right sidebar")

    ConfigSwitch {
        buttonIcon: "memory"
        text: Translation.tr('Keep right sidebar loaded')
        checked: Config.options.sidebar.keepRightSidebarLoaded
        onCheckedChanged: {
            Config.options.sidebar.keepRightSidebarLoaded = checked;
        }
        StyledToolTip {
            text: Translation.tr("When enabled keeps the content of the right sidebar loaded to reduce the delay when opening,\nat the cost of around 15MB of consistent RAM usage. Delay significance depends on your system's performance.\nUsing a custom kernel like linux-cachyos might help")
        }
    }

    ContentSubsection {
        title: Translation.tr("Quick toggles")

        ConfigSelectionArray {
            Layout.fillWidth: false
            currentValue: Config.options.sidebar.quickToggles.style
            onSelected: newValue => {
                Config.options.sidebar.quickToggles.style = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("Classic"),
                    icon: "password_2",
                    value: "classic"
                },
                {
                    displayName: Translation.tr("Android"),
                    icon: "action_key",
                    value: "android"
                }
            ]
        }

        ConfigSpinBox {
            enabled: Config.options.sidebar.quickToggles.style === "android"
            icon: "splitscreen_left"
            text: Translation.tr("Columns")
            value: Config.options.sidebar.quickToggles.android.columns
            from: 1
            to: 8
            stepSize: 1
            onValueChanged: {
                Config.options.sidebar.quickToggles.android.columns = value;
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Sliders")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: Config.options.sidebar.quickSliders.enable
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.enable = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "brightness_6"
            text: Translation.tr("Brightness")
            enabled: Config.options.sidebar.quickSliders.enable
            checked: Config.options.sidebar.quickSliders.showBrightness
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showBrightness = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "volume_up"
            text: Translation.tr("Volume")
            enabled: Config.options.sidebar.quickSliders.enable
            checked: Config.options.sidebar.quickSliders.showVolume
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showVolume = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "mic"
            text: Translation.tr("Microphone")
            enabled: Config.options.sidebar.quickSliders.enable
            checked: Config.options.sidebar.quickSliders.showMic
            onCheckedChanged: {
                Config.options.sidebar.quickSliders.showMic = checked;
            }
        }
    }
}
