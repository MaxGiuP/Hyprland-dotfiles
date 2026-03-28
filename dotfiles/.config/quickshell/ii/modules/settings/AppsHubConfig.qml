import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760

    function parseJson(text, fallback) {
        try {
            return JSON.parse(text)
        } catch (error) {
            return fallback
        }
    }

    function normalizedJson(value) {
        return JSON.stringify(value, null, 2)
    }

    ContentSection {
        icon: "apps"
        title: Translation.tr("Apps")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Choose the commands that this shell uses for system apps, and control which apps are pinned into the launcher.")
        }
    }

    ContentSection {
        icon: "terminal"
        title: Translation.tr("System app commands")

        Repeater {
            model: [
                { label: Translation.tr("Bluetooth settings command"), key: "bluetooth" },
                { label: Translation.tr("Network settings command"), key: "network" },
                { label: Translation.tr("Ethernet settings command"), key: "networkEthernet" },
                { label: Translation.tr("User management command"), key: "manageUser" },
                { label: Translation.tr("Change password command"), key: "changePassword" },
                { label: Translation.tr("Task manager command"), key: "taskManager" },
                { label: Translation.tr("Terminal command"), key: "terminal" },
                { label: Translation.tr("System update command"), key: "update" },
                { label: Translation.tr("Volume mixer command"), key: "volumeMixer" }
            ]

            delegate: MaterialTextArea {
                required property var modelData
                Layout.fillWidth: true
                placeholderText: modelData.label
                text: Config.options.apps[modelData.key]
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.apps[modelData.key] = text
            }
        }
    }

    ContentSection {
        icon: "apps"
        title: Translation.tr("Launcher")

        ContentSubsection {
            title: Translation.tr("Pinned apps")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("[\"org.kde.dolphin\", \"kitty\", \"cmake-gui\"]")
                text: root.normalizedJson(Config.options.launcher.pinnedApps)
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    const parsed = root.parseJson(text, null)
                    if (parsed !== null && Array.isArray(parsed))
                        Config.options.launcher.pinnedApps = parsed
                }
            }
        }
    }
}
