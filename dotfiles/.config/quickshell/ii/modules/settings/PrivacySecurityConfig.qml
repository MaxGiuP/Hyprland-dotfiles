import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true
    baseWidth: 760

    ContentSection {
        icon: "privacy_tip"
        title: Translation.tr("Security & privacy")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Privacy-sensitive shell behavior and policy gates are grouped here so they are easier to reason about as one set.")
        }
    }

    ContentSection {
        icon: "policy"
        title: Translation.tr("Policies")

        ContentSubsection {
            title: Translation.tr("AI policy")

            ConfigSelectionArray {
                currentValue: Config.options.policies.ai
                onSelected: newValue => Config.options.policies.ai = newValue
                options: [
                    { displayName: Translation.tr("No"), icon: "close", value: 0 },
                    { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                    { displayName: Translation.tr("Local only"), icon: "sync_saved_locally", value: 2 }
                ]
            }
        }
    }

    ContentSection {
        icon: "shield"
        title: Translation.tr("Content safety")

        ConfigSwitch {
            buttonIcon: "assignment"
            text: Translation.tr("Hide potentially sensitive clipboard images")
            checked: Config.options.workSafety.enable.clipboard
            onCheckedChanged: Config.options.workSafety.enable.clipboard = checked
        }

        ConfigSwitch {
            buttonIcon: "wallpaper"
            text: Translation.tr("Hide potentially sensitive wallpapers")
            checked: Config.options.workSafety.enable.wallpaper
            onCheckedChanged: Config.options.workSafety.enable.wallpaper = checked
        }
    }
}
