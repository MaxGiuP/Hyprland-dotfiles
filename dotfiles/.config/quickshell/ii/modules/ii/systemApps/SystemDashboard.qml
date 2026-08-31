import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

Item {
    id: root

    property int currentTab: 0
    readonly property var tabs: [
        { name: "Today", icon: "today" },
        { name: "Modes", icon: "tune" },
        { name: "Workspaces", icon: "grid_view" },
        { name: "Privacy", icon: "shield_lock" },
        { name: "Widgets", icon: "widgets" }
    ]

    component MetricCard: Rectangle {
        property string iconName: "info"
        property string label: ""
        property string value: ""
        property color accent: Appearance.colors.colPrimary
        Layout.fillWidth: true
        implicitHeight: 86
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            MaterialSymbol { text: parent.parent.iconName; iconSize: 26; color: parent.parent.accent }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText { text: parent.parent.parent.label; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small }
                StyledText { Layout.fillWidth: true; text: parent.parent.parent.value; color: Appearance.colors.colOnLayer1; font.weight: Font.DemiBold; elide: Text.ElideRight }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        SecondaryTabBar {
            id: tabBar
            Layout.fillWidth: true
            currentIndex: root.currentTab
            onCurrentIndexChanged: root.currentTab = currentIndex

            Repeater {
                model: root.tabs
                delegate: SecondaryTabButton {
                    required property var modelData
                    buttonIcon: modelData.icon
                    buttonText: modelData.name
                }
            }
        }

        SwipeView {
            id: pages
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTab
            onCurrentIndexChanged: root.currentTab = currentIndex
            clip: true

            // Today: a compact daily dashboard plus health overview.
            Item {
                StyledFlickable {
                    anchors.fill: parent
                    contentHeight: todayColumn.implicitHeight + 24
                    clip: true

                    ColumnLayout {
                        id: todayColumn
                        width: parent.width
                        anchors.margins: 12
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true
                                StyledText { text: DateTime.time; font.pixelSize: Appearance.font.pixelSize.massive; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                                StyledText { text: DateTime.longDate; color: Appearance.colors.colSubtext }
                            }
                            Rectangle {
                                radius: Appearance.rounding.full
                                color: SystemHealth.healthy ? Appearance.colors.colPrimaryContainer : Appearance.colors.colErrorContainer
                                implicitWidth: healthLabel.implicitWidth + 24
                                implicitHeight: healthLabel.implicitHeight + 12
                                StyledText {
                                    id: healthLabel
                                    anchors.centerIn: parent
                                    text: SystemHealth.healthy ? "System healthy" : "Attention needed"
                                    color: SystemHealth.healthy ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: width < 700 ? 2 : 4
                            columnSpacing: 10
                            rowSpacing: 10
                            MetricCard { iconName: "developer_board"; label: "CPU"; value: `${Math.round(ResourceUsage.cpuUsage * 100)}%` }
                            MetricCard { iconName: "memory"; label: "Memory"; value: `${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%` }
                            MetricCard { iconName: "thermostat"; label: "CPU temperature"; value: `${SystemHealth.temperature}°C`; accent: SystemHealth.temperature >= 85 ? Appearance.colors.colError : Appearance.colors.colPrimary }
                            MetricCard { iconName: "hard_drive"; label: "Root disk"; value: `${SystemHealth.diskPercent}% used`; accent: SystemHealth.diskPercent >= 90 ? Appearance.colors.colError : Appearance.colors.colPrimary }
                            MetricCard { iconName: "jamboard_kiosk"; label: "GPU"; value: `${SystemMetrics.gpuUtil}% • ${SystemMetrics.vramPercent}% VRAM` }
                            MetricCard { iconName: "network_check"; label: "Network"; value: `↓ ${SystemMetrics.netDisplayDown.toFixed(1)} ↑ ${SystemMetrics.netDisplayUp.toFixed(1)} ${SystemMetrics.netDisplayUnit}` }
                            MetricCard { iconName: "system_update"; label: "Updates"; value: Updates.checking ? "Checking…" : `${Updates.count} available` }
                            MetricCard { iconName: "event_note"; label: "Agenda & mail"; value: `${UnifiedAgenda.openLocalTaskCount + UnifiedAgenda.openRemoteTaskCount} tasks • ${UnifiedAgenda.unreadCount} unread` }
                        }

                        ContentSection {
                            Layout.fillWidth: true
                            icon: "monitor_heart"
                            title: "Shell health"
                            description: `${SystemHealth.warningCount} warnings this boot • ${SystemHealth.crashCount} crashes`

                            Repeater {
                                model: Object.keys(SystemHealth.services)
                                delegate: RowLayout {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    MaterialSymbol { text: SystemHealth.services[modelData] === "active" ? "check_circle" : "error"; color: SystemHealth.services[modelData] === "active" ? Appearance.colors.colPrimary : Appearance.colors.colError }
                                    StyledText { Layout.fillWidth: true; text: modelData.replace(".service", ""); color: Appearance.colors.colOnLayer1 }
                                    StyledText { text: SystemHealth.services[modelData]; color: Appearance.colors.colSubtext }
                                }
                            }

                            ConfigRow {
                                uniform: true
                                RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "refresh"; mainText: "Refresh"; onClicked: SystemHealth.refresh() }
                                RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "restart_alt"; mainText: "Restart bridges"; onClicked: SystemHealth.restartBridges() }
                                RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "terminal"; mainText: "Live logs"; onClicked: SystemHealth.openLogs() }
                            }
                        }

                        ContentSection {
                            Layout.fillWidth: true
                            icon: "task_alt"
                            title: "Next up"
                            Repeater {
                                model: UnifiedAgenda.agendaItems.slice(0, 5)
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    MaterialSymbol { text: modelData.kind === "event" ? "event" : "radio_button_unchecked"; color: Appearance.colors.colPrimary }
                                    StyledText { Layout.fillWidth: true; text: modelData.title; color: Appearance.colors.colOnLayer1; elide: Text.ElideRight }
                                    StyledText { visible: modelData.account.length > 0; text: modelData.account; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
                                }
                            }
                            StyledText { visible: UnifiedAgenda.agendaItems.length === 0; text: "Nothing pending."; color: Appearance.colors.colSubtext }
                        }
                    }
                }
            }

            // Desktop scenes and audio routing presets.
            Item {
                StyledFlickable {
                    anchors.fill: parent
                    contentHeight: modesColumn.implicitHeight + 24
                    clip: true
                    ColumnLayout {
                        id: modesColumn
                        width: parent.width
                        spacing: 12

                        ContentSection {
                            Layout.fillWidth: true
                            icon: "tune"
                            title: "Desktop modes"
                            description: "Switch power, interruption, idle and shell behaviour together"
                            GridLayout {
                                Layout.fillWidth: true
                                columns: width < 650 ? 1 : 2
                                columnSpacing: 8
                                rowSpacing: 8
                                Repeater {
                                    model: DesktopModes.modes
                                    delegate: RippleButtonWithIcon {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        materialIcon: modelData.icon
                                        mainText: modelData.name
                                        toggled: DesktopModes.currentMode === modelData.id
                                        onClicked: DesktopModes.apply(modelData.id)
                                    }
                                }
                            }
                        }

                        ContentSection {
                            Layout.fillWidth: true
                            icon: "speaker_group"
                            title: "Audio scenes"
                            description: `Current output: ${Audio.currentSinkDisplayName}`
                            ConfigRow {
                                uniform: true
                                Repeater {
                                    model: AudioScenes.scenes
                                    delegate: RippleButtonWithIcon {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        materialIcon: modelData.icon
                                        mainText: modelData.name
                                        toggled: AudioScenes.lastScene === modelData.id
                                        onClicked: AudioScenes.apply(modelData.id)
                                    }
                                }
                            }
                            StyledText { visible: AudioScenes.lastError.length > 0; text: AudioScenes.lastError; color: Appearance.colors.colError }
                        }
                    }
                }
            }

            // The 30 persistent workspaces grouped into their monitor banks.
            Item {
                StyledFlickable {
                    anchors.fill: parent
                    contentHeight: atlasColumn.implicitHeight + 24
                    clip: true
                    ColumnLayout {
                        id: atlasColumn
                        width: parent.width
                        spacing: 12
                        StyledText { text: "Workspace atlas"; font.pixelSize: Appearance.font.pixelSize.huge; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                        StyledText { text: "Your persistent workspaces are grouped by display bank. Click one to switch."; color: Appearance.colors.colSubtext }

                        Repeater {
                            model: [
                                { name: "Primary • DP-1", start: 1 },
                                { name: "Secondary • HDMI-A-1", start: 11 },
                                { name: "TV • HDMI-A-2", start: 21 }
                            ]
                            delegate: ContentSection {
                                required property var modelData
                                Layout.fillWidth: true
                                icon: modelData.start === 21 ? "tv" : "desktop_windows"
                                title: modelData.name
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 5
                                    columnSpacing: 8
                                    rowSpacing: 8
                                    Repeater {
                                        model: 10
                                        delegate: RippleButton {
                                            required property int index
                                            readonly property int workspaceId: parent.parent.parent.modelData.start + index
                                            Layout.fillWidth: true
                                            implicitHeight: 60
                                            buttonRadius: Appearance.rounding.normal
                                            colBackground: HyprlandData.activeWorkspace?.id === workspaceId ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                                            onClicked: Hyprland.dispatch(`workspace ${workspaceId}`)
                                            contentItem: ColumnLayout {
                                                anchors.centerIn: parent
                                                StyledText { Layout.alignment: Qt.AlignHCenter; text: parent.parent.workspaceId; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer1 }
                                                StyledText { Layout.alignment: Qt.AlignHCenter; text: `${HyprlandData.hyprlandClientsForWorkspace(parent.parent.workspaceId).length} windows`; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                StyledFlickable {
                    anchors.fill: parent
                    contentHeight: privacyColumn.implicitHeight + 24
                    clip: true
                    ColumnLayout {
                        id: privacyColumn
                        width: parent.width
                        spacing: 12

                        ContentSection {
                            Layout.fillWidth: true
                            icon: "shield_lock"
                            title: "Privacy dashboard"
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 10
                                rowSpacing: 10
                                MetricCard { iconName: Privacy.screenSharing ? "screen_share" : "stop_screen_share"; label: "Screen sharing"; value: Privacy.screenSharing ? "Active" : "Inactive"; accent: Privacy.screenSharing ? Appearance.colors.colError : Appearance.colors.colPrimary }
                                MetricCard { iconName: Privacy.micActive ? "mic" : "mic_off"; label: "Microphone use"; value: Privacy.micActive ? "In use" : "Idle"; accent: Privacy.micActive ? Appearance.colors.colError : Appearance.colors.colPrimary }
                            }
                            ConfigRow {
                                uniform: true
                                ConfigSwitch { Layout.fillWidth: true; buttonIcon: Audio.micMuted ? "mic_off" : "mic"; text: "Mute microphone"; checked: Audio.micMuted; onClicked: Audio.toggleMicMute() }
                                ConfigSwitch { Layout.fillWidth: true; buttonIcon: Notifications.silent ? "notifications_off" : "notifications"; text: "Do not disturb"; checked: Notifications.silent; onClicked: Notifications.silent = !Notifications.silent }
                                ConfigSwitch { Layout.fillWidth: true; buttonIcon: Idle.inhibit ? "bedtime_off" : "bedtime"; text: "Keep awake"; checked: Idle.inhibit; onClicked: Idle.toggleInhibit() }
                            }
                        }
                    }
                }
            }

            Item {
                StyledFlickable {
                    anchors.fill: parent
                    contentHeight: widgetColumn.implicitHeight + 24
                    clip: true
                    ColumnLayout {
                        id: widgetColumn
                        width: parent.width
                        spacing: 12
                        ContentSection {
                            Layout.fillWidth: true
                            icon: "widgets"
                            title: "Widget studio"
                            description: "Compose the desktop without opening the full settings app"
                            ConfigRow {
                                uniform: true
                                ConfigSwitch { Layout.fillWidth: true; buttonIcon: "schedule"; text: "Desktop clock"; checked: Config.options.background.widgets.clock.enable; onClicked: Config.options.background.widgets.clock.enable = !Config.options.background.widgets.clock.enable }
                                ConfigSwitch { Layout.fillWidth: true; buttonIcon: "partly_cloudy_day"; text: "Desktop weather"; checked: Config.options.background.widgets.weather.enable; onClicked: Config.options.background.widgets.weather.enable = !Config.options.background.widgets.weather.enable }
                                ConfigSwitch { Layout.fillWidth: true; buttonIcon: "wb_cloudy"; text: "Bar weather"; checked: Config.options.bar.weather.enable; onClicked: Config.options.bar.weather.enable = !Config.options.bar.weather.enable }
                                ConfigSwitch { Layout.fillWidth: true; buttonIcon: "dock_to_bottom"; text: "Dock"; checked: Config.options.dock.enable; onClicked: Config.options.dock.enable = !Config.options.dock.enable }
                            }
                            ConfigRow {
                                uniform: true
                                RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "schedule"; mainText: "Cookie clock"; toggled: Config.options.background.widgets.clock.style === "cookie"; onClicked: Config.options.background.widgets.clock.style = "cookie" }
                                RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "digital_out_of_home"; mainText: "Digital clock"; toggled: Config.options.background.widgets.clock.style === "digital"; onClicked: Config.options.background.widgets.clock.style = "digital" }
                                RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "settings"; mainText: "Full settings"; onClicked: Quickshell.execDetached(["qs", "-p", `${Directories.shellConfigPath}/settings.qml`]) }
                            }
                        }
                    }
                }
            }
        }
    }
}
