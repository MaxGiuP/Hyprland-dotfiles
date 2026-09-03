import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760

    property int currentTab: 0
    property var toolPaths: ({})
    property var pendingToolPaths: ({})
    property bool toolsLoading: false

    readonly property var tabs: [
        { name: Translation.tr("Game mode"), icon: "sports_esports" },
        { name: Translation.tr("Performance"), icon: "speed" },
        { name: Translation.tr("Tools"), icon: "build" }
    ]

    readonly property var toolEntries: [
        { id: "steam", name: "Steam", icon: "sports_esports", detail: Translation.tr("Game library and launcher"), launchable: true },
        { id: "gamescope", name: "Gamescope", icon: "fullscreen", detail: Translation.tr("Micro-compositor for isolated game sessions"), launchable: false },
        { id: "gamemode", name: "GameMode", icon: "rocket_launch", detail: Translation.tr("Temporary system performance optimisation"), launchable: false },
        { id: "mangohud", name: "MangoHud", icon: "monitoring", detail: Translation.tr("Vulkan and OpenGL performance overlay"), launchable: false },
        { id: "goverlay", name: "GOverlay", icon: "tune", detail: Translation.tr("Graphical MangoHud configuration"), launchable: true },
        { id: "lutris", name: "Lutris", icon: "stadia_controller", detail: Translation.tr("Cross-platform game library"), launchable: true },
        { id: "heroic", name: "Heroic", icon: "swords", detail: Translation.tr("Epic, GOG and Amazon game launcher"), launchable: true }
    ]

    readonly property string powerProfileName: {
        switch (PowerProfiles.profile) {
        case PowerProfile.PowerSaver:
            return Translation.tr("Power saver")
        case PowerProfile.Performance:
            return Translation.tr("Performance")
        default:
            return Translation.tr("Balanced")
        }
    }

    readonly property string degradationReason: {
        switch (PowerProfiles.degradationReason) {
        case PerformanceDegradationReason.LapDetected:
            return Translation.tr("Performance is limited while the device is on a lap")
        case PerformanceDegradationReason.HighTemperature:
            return Translation.tr("Performance is limited because the device is hot")
        default:
            return ""
        }
    }

    function applySubTab(subTab, sectionId = "") {
        currentTab = Math.max(0, Math.min(Number(subTab), tabs.length - 1))
        contentY = 0
    }

    function hasTool(toolId) {
        return String(toolPaths[toolId] || "").length > 0
    }

    function launchTool(toolId) {
        if (!hasTool(toolId))
            return
        if (!["steam", "goverlay", "lutris", "heroic"].includes(toolId))
            return
        Quickshell.execDetached([toolPaths[toolId]])
    }

    function launchGamescopeSteam() {
        if (!hasTool("gamescope") || !hasTool("steam"))
            return
        Quickshell.execDetached([toolPaths.gamescope, "-f", "--", toolPaths.steam, "-gamepadui"])
    }

    function refreshTools() {
        toolDetectionProc.running = false
        toolDetectionProc.running = true
    }

    Component.onCompleted: refreshTools()

    Process {
        id: toolDetectionProc
        command: ["bash", "-lc",
            "for command_name in steam gamescope gamemoderun mangohud goverlay lutris heroic heroic-games-launcher; do " +
            "  command_path=$(command -v \"$command_name\" 2>/dev/null) || continue; " +
            "  printf '%s\\t%s\\n' \"$command_name\" \"$command_path\"; " +
            "done"
        ]

        onRunningChanged: {
            if (running) {
                root.toolsLoading = true
                root.pendingToolPaths = ({})
            }
        }

        stdout: SplitParser {
            onRead: line => {
                const fields = line.split("\t")
                if (fields.length < 2)
                    return
                let toolId = fields[0].trim()
                if (toolId === "gamemoderun")
                    toolId = "gamemode"
                else if (toolId === "heroic-games-launcher")
                    toolId = "heroic"
                const nextPaths = Object.assign({}, root.pendingToolPaths)
                if (!nextPaths[toolId])
                    nextPaths[toolId] = fields.slice(1).join("\t").trim()
                root.pendingToolPaths = nextPaths
            }
        }

        onExited: {
            root.toolPaths = root.pendingToolPaths
            root.toolsLoading = false
        }
    }

    component StatusCard: Rectangle {
        id: statusCard
        property string iconName: "info"
        property string label: ""
        property string value: ""

        Layout.fillWidth: true
        implicitHeight: statusContent.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        RowLayout {
            id: statusContent
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: Appearance.rounding.small
                color: Appearance.colors.colSecondaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: statusCard.iconName
                    iconSize: 21
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: statusCard.label
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                StyledText {
                    Layout.fillWidth: true
                    text: statusCard.value
                    color: Appearance.colors.colOnLayer1
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }
        }
    }

    component ToolCard: Rectangle {
        id: toolCard
        required property var entry
        readonly property bool installed: root.hasTool(entry.id)

        Layout.fillWidth: true
        implicitHeight: toolContent.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        RowLayout {
            id: toolContent
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                radius: Appearance.rounding.small
                color: toolCard.installed
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colSecondaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: toolCard.entry.icon
                    iconSize: 22
                    color: toolCard.installed
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: toolCard.entry.name
                    color: Appearance.colors.colOnLayer1
                    font.weight: Font.Medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: toolCard.entry.detail
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
            }

            StyledText {
                text: toolCard.installed ? Translation.tr("Installed") : Translation.tr("Unavailable")
                color: toolCard.installed ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }

            RippleButtonWithIcon {
                visible: toolCard.entry.launchable
                enabled: toolCard.installed
                Layout.preferredWidth: implicitWidth
                materialIcon: "open_in_new"
                mainText: ""
                onClicked: root.launchTool(toolCard.entry.id)

                StyledToolTip {
                    text: Translation.tr("Open %1").arg(toolCard.entry.name)
                }
            }
        }
    }

    SecondaryTabBar {
        Layout.fillWidth: true
        currentIndex: root.currentTab
        onCurrentIndexChanged: {
            root.currentTab = currentIndex
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

    Connections {
        target: DesktopModes
        function onCurrentModeChanged() {
            gameModeSwitch.checked = DesktopModes.currentMode === "gaming"
        }
    }

    Connections {
        target: Notifications
        function onSilentChanged() {
            gamingQuietSwitch.checked = Notifications.silent
        }
    }

    Connections {
        target: Idle
        function onInhibitChanged() {
            gamingAwakeSwitch.checked = Idle.inhibit
        }
    }

    ContentSection {
        visible: root.currentTab === 0
        icon: "sports_esports"
        title: Translation.tr("Game mode")
        description: DesktopModes.currentMode === "gaming"
            ? Translation.tr("Gaming optimisations are active")
            : Translation.tr("Gaming optimisations are off")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "bolt"
            text: Translation.tr("Game mode combines the performance power profile, do not disturb, hidden desktop chrome and idle inhibition. Returning to Balanced restores the previous state.")
        }

        ConfigSwitch {
            id: gameModeSwitch
            buttonIcon: "sports_esports"
            text: Translation.tr("Enable game mode")
            checked: DesktopModes.currentMode === "gaming"
            onClicked: DesktopModes.apply(gameModeSwitch.checked ? "gaming" : "balanced")
        }

    }

    ContentSection {
        visible: root.currentTab === 0
        icon: "tune"
        title: Translation.tr("Session mode")

        ConfigRow {
            preferredColumns: 3
            collapseWidth: 680
            uniform: true

            Repeater {
                model: DesktopModes.modes
                delegate: RippleButtonWithIcon {
                    required property var modelData
                    Layout.fillWidth: true
                    materialIcon: modelData.icon
                    mainText: Translation.tr(modelData.name)
                    toggled: DesktopModes.currentMode === modelData.id
                    onClicked: DesktopModes.apply(modelData.id)

                    StyledToolTip {
                        text: Translation.tr(modelData.detail)
                    }
                }
            }
        }
    }

    ContentSection {
        visible: root.currentTab === 0
        icon: "handyman"
        title: Translation.tr("Manual controls")

        ConfigRow {
            uniform: true

            ConfigSwitch {
                id: gamingQuietSwitch
                buttonIcon: Notifications.silent ? "notifications_off" : "notifications"
                text: Translation.tr("Silence pop-ups")
                checked: Notifications.silent
                onClicked: Notifications.silent = gamingQuietSwitch.checked
            }

            ConfigSwitch {
                id: gamingAwakeSwitch
                buttonIcon: Idle.inhibit ? "bedtime_off" : "bedtime"
                text: Translation.tr("Keep display awake")
                checked: Idle.inhibit
                onClicked: Idle.toggleInhibit(gamingAwakeSwitch.checked)
            }
        }
    }

    ContentSection {
        visible: root.currentTab === 1
        icon: "speed"
        title: Translation.tr("Power profile")
        description: Translation.tr("Current profile: %1").arg(root.powerProfileName)

        ConfigRow {
            preferredColumns: 3
            collapseWidth: 640
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "energy_savings_leaf"
                mainText: Translation.tr("Power saver")
                toggled: PowerProfiles.profile === PowerProfile.PowerSaver
                onClicked: PowerProfiles.profile = PowerProfile.PowerSaver
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "balance"
                mainText: Translation.tr("Balanced")
                toggled: PowerProfiles.profile === PowerProfile.Balanced
                onClicked: PowerProfiles.profile = PowerProfile.Balanced
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                enabled: PowerProfiles.hasPerformanceProfile
                materialIcon: "local_fire_department"
                mainText: Translation.tr("Performance")
                toggled: PowerProfiles.profile === PowerProfile.Performance
                onClicked: PowerProfiles.profile = PowerProfile.Performance

                StyledToolTip {
                    text: PowerProfiles.hasPerformanceProfile
                        ? Translation.tr("Prioritise performance")
                        : Translation.tr("No performance profile is exposed by this system")
                }
            }
        }

        NoticeBox {
            visible: root.degradationReason.length > 0
            Layout.fillWidth: true
            materialIcon: "warning"
            text: root.degradationReason
        }
    }

    ContentSection {
        visible: root.currentTab === 1
        icon: "monitor_heart"
        title: Translation.tr("Live status")

        ConfigRow {
            uniform: true

            StatusCard {
                iconName: "battery_android_full"
                label: Translation.tr("Battery")
                value: Battery.available
                    ? Translation.tr("%1%").arg(Math.round(Battery.percentage * 100))
                    : Translation.tr("Desktop power")
            }

            StatusCard {
                iconName: "device_thermostat"
                label: Translation.tr("Temperature")
                value: SystemHealth.temperature > 0
                    ? Translation.tr("%1 °C").arg(SystemHealth.temperature)
                    : Translation.tr("Unavailable")
            }
        }

        ConfigRow {
            uniform: true

            StatusCard {
                iconName: "hard_drive"
                label: Translation.tr("Disk use")
                value: Translation.tr("%1%").arg(SystemHealth.diskPercent)
            }

            StatusCard {
                iconName: "notifications"
                label: Translation.tr("Interruptions")
                value: Notifications.silent
                    ? Translation.tr("Silenced")
                    : Translation.tr("Allowed")
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh system status")
            onClicked: SystemHealth.refresh()
        }
    }

    ContentSection {
        visible: root.currentTab === 2
        icon: "extension"
        title: Translation.tr("Gaming capabilities")
        description: root.toolsLoading
            ? Translation.tr("Detecting installed tools…")
            : Translation.tr("Detected directly from the executable search path")

        Repeater {
            model: root.toolEntries
            delegate: ToolCard {
                required property var modelData
                entry: modelData
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            enabled: !root.toolsLoading
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh capabilities")
            onClicked: root.refreshTools()
        }
    }

    ContentSection {
        visible: root.currentTab === 2
            && (root.hasTool("steam") || root.hasTool("lutris") || root.hasTool("heroic") || root.hasTool("goverlay"))
        icon: "play_circle"
        title: Translation.tr("Launch")

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                visible: root.hasTool("steam")
                Layout.fillWidth: true
                materialIcon: "sports_esports"
                mainText: "Steam"
                onClicked: root.launchTool("steam")
            }

            RippleButtonWithIcon {
                visible: root.hasTool("steam") && root.hasTool("gamescope")
                Layout.fillWidth: true
                materialIcon: "fullscreen"
                mainText: Translation.tr("Steam in Gamescope")
                onClicked: root.launchGamescopeSteam()
            }

            RippleButtonWithIcon {
                visible: root.hasTool("lutris")
                Layout.fillWidth: true
                materialIcon: "stadia_controller"
                mainText: "Lutris"
                onClicked: root.launchTool("lutris")
            }

            RippleButtonWithIcon {
                visible: root.hasTool("heroic")
                Layout.fillWidth: true
                materialIcon: "swords"
                mainText: "Heroic"
                onClicked: root.launchTool("heroic")
            }

            RippleButtonWithIcon {
                visible: root.hasTool("goverlay")
                Layout.fillWidth: true
                materialIcon: "monitoring"
                mainText: "GOverlay"
                onClicked: root.launchTool("goverlay")
            }
        }
    }
}
