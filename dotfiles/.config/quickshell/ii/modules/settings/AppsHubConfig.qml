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
            text: Translation.tr("Choose the commands that this shell uses for system apps, and control which apps are pinned into the dock and launcher surfaces.")
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
        icon: "dock_to_bottom"
        title: Translation.tr("Dock & launcher")

        ConfigRow {
            uniform: true

            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Dock height")
                value: Config.options.dock.height
                from: 36
                to: 160
                stepSize: 2
                onValueChanged: Config.options.dock.height = value
            }

            ConfigSpinBox {
                icon: "gesture"
                text: Translation.tr("Reveal edge height")
                value: Config.options.dock.hoverRegionHeight
                from: 1
                to: 40
                stepSize: 1
                onValueChanged: Config.options.dock.hoverRegionHeight = value
            }
        }

        ContentSubsection {
            title: Translation.tr("Pinned apps")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("[\"org.kde.dolphin\", \"kitty\"]")
                text: root.normalizedJson(Config.options.dock.pinnedApps)
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    const parsed = root.parseJson(text, null)
                    if (parsed !== null && Array.isArray(parsed))
                        Config.options.dock.pinnedApps = parsed
                }
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("[\"^steam_app_.*$\"]")
                text: root.normalizedJson(Config.options.dock.ignoredAppRegexes)
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    const parsed = root.parseJson(text, null)
                    if (parsed !== null && Array.isArray(parsed))
                        Config.options.dock.ignoredAppRegexes = parsed
                }
            }

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
