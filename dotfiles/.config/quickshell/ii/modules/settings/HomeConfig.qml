import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760
    readonly property bool settingsApp: Quickshell.env("II_SETTINGS_APP") === "1"
    property var settingsHost: null

    readonly property var trackedOutputDevices: Audio.outputDevices.filter(d => d.name !== "qs_mono_out")
    readonly property var realOutputDevices: Audio.selectableOutputDevices.filter(d => d.name !== "qs_mono_out")
    readonly property var dashboardAgenda: UnifiedAgenda.agendaItems.slice(0, 7)
    readonly property var dashboardMail: UnifiedAgenda.recentMail.slice(0, 10)
    property int dashboardTab: 0
    readonly property var dashboardTabs: [
        { name: Translation.tr("Overview"), icon: "space_dashboard" },
        { name: Translation.tr("Agenda"), icon: "event_upcoming" },
        { name: Translation.tr("Inbox"), icon: "all_inbox" },
        { name: Translation.tr("Controls"), icon: "tune" },
    ]

    function formatAgendaTime(timestamp, allDay = false) {
        if (!timestamp) return Translation.tr("Any time")
        const date = new Date(timestamp)
        const today = new Date()
        const sameDay = date.getFullYear() === today.getFullYear()
            && date.getMonth() === today.getMonth()
            && date.getDate() === today.getDate()
        const day = sameDay ? Translation.tr("Today") : Translation.locale.toString(date, "ddd d MMM")
        return allDay ? day : `${day} • ${Translation.locale.toString(date, "HH:mm")}`
    }

    function formatMailTime(timestamp) {
        if (!timestamp) return ""
        const date = new Date(timestamp)
        const age = Date.now() - timestamp
        return age < 24 * 60 * 60 * 1000
            ? Translation.locale.toString(date, "HH:mm")
            : Translation.locale.toString(date, "d MMM")
    }

    function navigate(page, subTab = -1, sectionId = "") {
        const host = root.settingsHost ?? Window.window
        if (!host)
            return
        host.requestedSubTab = subTab
        host.requestedSectionId = sectionId
        host.currentPage = page
    }

    PwObjectTracker {
        objects: root.trackedOutputDevices
    }

    ContentSection {
        icon: "space_dashboard"
        title: Translation.tr("Dashboard")
        description: `${DateTime.longDate} • ${DateTime.time}`

        SecondaryTabBar {
            id: dashboardTabBar
            Layout.fillWidth: true
            currentIndex: root.dashboardTab
            onCurrentIndexChanged: root.dashboardTab = currentIndex

            Repeater {
                model: root.dashboardTabs
                delegate: SecondaryTabButton {
                    required property var modelData
                    buttonText: modelData.name
                    buttonIcon: modelData.icon
                }
            }
        }

        ConfigRow {
            visible: root.dashboardTab === 0
            preferredColumns: 4
            collapseWidth: 720
            uniform: true

            HomeStatusButton {
                iconName: SystemHealth.healthy ? "check_circle" : "monitor_heart"
                label: Translation.tr("System")
                value: SystemHealth.healthy ? Translation.tr("Healthy") : Translation.tr("Needs attention")
                onClicked: root.dashboardTab = 3
            }

            HomeStatusButton {
                iconName: "event"
                label: Translation.tr("Agenda")
                value: Translation.tr("%1 upcoming").arg(UnifiedAgenda.agendaItems.length)
                onClicked: root.dashboardTab = 1
            }

            HomeStatusButton {
                iconName: UnifiedAgenda.unreadCount > 0 ? "mark_email_unread" : "mail"
                label: Translation.tr("Mail")
                value: Translation.tr("%1 unread").arg(UnifiedAgenda.unreadCount)
                onClicked: root.dashboardTab = 2
            }

            HomeStatusButton {
                iconName: "task_alt"
                label: Translation.tr("Tasks")
                value: Translation.tr("%1 open").arg(UnifiedAgenda.openLocalTaskCount + UnifiedAgenda.openRemoteTaskCount)
                onClicked: {
                    root.dashboardTab = 1
                    Qt.callLater(() => quickTaskInput.forceActiveFocus())
                }
            }
        }

        GridLayout {
            visible: root.dashboardTab <= 2
            Layout.fillWidth: true
            columns: root.dashboardTab === 0 && width >= 740 ? 2 : 1
            columnSpacing: 10
            rowSpacing: 10
            uniformCellWidths: true

            DashboardPanel {
                visible: root.dashboardTab === 0 || root.dashboardTab === 1
                title: Translation.tr("Unified agenda")
                iconName: "calendar_month"

                Repeater {
                    model: root.dashboardAgenda.slice(0, root.dashboardTab === 0 ? 3 : 7)
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 8

                            MaterialSymbol {
                                text: modelData.kind === "event" ? "event" : modelData.source === "mail" ? "forward_to_inbox" : "check_box_outline_blank"
                                iconSize: 18
                                color: modelData.kind === "event" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText { Layout.fillWidth: true; text: modelData.title; color: Appearance.colors.colOnLayer1; elide: Text.ElideRight; font.weight: Font.Medium }
                                StyledText { Layout.fillWidth: true; text: `${root.formatAgendaTime(modelData.timestamp, modelData.allDay)}${modelData.account ? ` • ${modelData.account}` : ""}`; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller; elide: Text.ElideRight }
                            }

                            RippleButton {
                                visible: modelData.kind === "event" && !UnifiedAgenda.hasTaskForExternalId(`event:${modelData.externalId}`)
                                implicitWidth: 32
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.full
                                onClicked: UnifiedAgenda.addEventAsTask(modelData)
                                contentItem: MaterialSymbol { anchors.centerIn: parent; text: "playlist_add"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            }
                        }
                    }
                }

                StyledText {
                    visible: root.dashboardAgenda.length === 0
                    Layout.fillWidth: true
                    text: UnifiedAgenda.loading ? Translation.tr("Refreshing agenda…") : Translation.tr("Nothing upcoming")
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colSubtext
                }
            }

            DashboardPanel {
                visible: root.dashboardTab === 0 || root.dashboardTab === 2
                title: Translation.tr("Unified inbox")
                iconName: "all_inbox"

                Repeater {
                    model: root.dashboardMail.slice(0, root.dashboardTab === 0 ? 3 : 10)
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: Appearance.rounding.small
                        color: modelData.read ? Appearance.colors.colLayer1 : Appearance.colors.colSecondaryContainer

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 8

                            MaterialSymbol { text: modelData.starred ? "star" : modelData.read ? "mail" : "mark_email_unread"; iconSize: 18; color: modelData.read ? Appearance.colors.colSubtext : Appearance.colors.colOnSecondaryContainer }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText { Layout.fillWidth: true; text: modelData.title; color: modelData.read ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnSecondaryContainer; elide: Text.ElideRight; font.weight: modelData.read ? Font.Normal : Font.DemiBold }
                                StyledText { Layout.fillWidth: true; text: `${modelData.author || modelData.provider} • ${modelData.account}`; color: modelData.read ? Appearance.colors.colSubtext : Appearance.colors.colOnSecondaryContainer; font.pixelSize: Appearance.font.pixelSize.smaller; elide: Text.ElideRight }
                            }

                            StyledText { text: root.formatMailTime(modelData.timestamp); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }

                            RippleButton {
                                implicitWidth: 32
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.full
                                enabled: !UnifiedAgenda.hasTaskForExternalId(`mail:${modelData.accountId}:${modelData.id}`)
                                onClicked: UnifiedAgenda.addMailAsTask(modelData)
                                contentItem: MaterialSymbol { anchors.centerIn: parent; text: parent.enabled ? "add_task" : "task_alt"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            }
                        }
                    }
                }

                StyledText {
                    visible: root.dashboardMail.length === 0
                    Layout.fillWidth: true
                    text: UnifiedAgenda.mailError || Translation.tr("No indexed messages")
                    horizontalAlignment: Text.AlignHCenter
                    color: UnifiedAgenda.mailError ? Appearance.colors.colError : Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }
        }

        RowLayout {
            visible: root.dashboardTab === 1
            Layout.fillWidth: true
            spacing: 8

            MaterialTextField {
                id: quickTaskInput
                Layout.fillWidth: true
                placeholderText: Translation.tr("Add a task to the unified agenda")
                onAccepted: {
                    if (text.trim().length > 0) {
                        Todo.addTask(text.trim())
                        text = ""
                    }
                }
            }

            DialogButton {
                buttonText: Translation.tr("Add")
                enabled: quickTaskInput.text.trim().length > 0
                onClicked: {
                    Todo.addTask(quickTaskInput.text.trim())
                    quickTaskInput.text = ""
                }
            }

        }

        ConfigRow {
            visible: root.dashboardTab <= 2
            uniform: true
            RippleButtonWithIcon { visible: root.dashboardTab === 0 || root.dashboardTab === 2; Layout.fillWidth: true; materialIcon: "mail"; mainText: Translation.tr("Open mail"); onClicked: UnifiedAgenda.openMail() }
            RippleButtonWithIcon { visible: root.dashboardTab === 0 || root.dashboardTab === 1; Layout.fillWidth: true; materialIcon: "calendar_month"; mainText: Translation.tr("Open calendar"); onClicked: UnifiedAgenda.openCalendar() }
            RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "manage_accounts"; mainText: Translation.tr("Connected accounts"); onClicked: root.navigate(6) }
            RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "refresh"; mainText: Translation.tr("Refresh all"); onClicked: UnifiedAgenda.refresh() }
        }

        DashboardPanel {
            visible: root.dashboardTab === 3
            iconName: "tune"
            title: Translation.tr("Desktop modes and privacy")

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Apply a scene or change interruption controls without leaving Settings")
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            GridLayout {
                Layout.fillWidth: true
                columns: width < 700 ? 2 : 3
                columnSpacing: 8
                rowSpacing: 8
                uniformCellWidths: true

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

            ConfigRow {
                uniform: true
                ConfigSwitch { Layout.fillWidth: true; buttonIcon: Notifications.silent ? "notifications_off" : "notifications"; text: Translation.tr("Do not disturb"); checked: Notifications.silent; onClicked: Notifications.silent = !Notifications.silent }
                ConfigSwitch { Layout.fillWidth: true; buttonIcon: Audio.micMuted ? "mic_off" : "mic"; text: Translation.tr("Mute microphone"); checked: Audio.micMuted; onClicked: Audio.toggleMicMute() }
                ConfigSwitch { Layout.fillWidth: true; buttonIcon: Idle.inhibit ? "bedtime_off" : "bedtime"; text: Translation.tr("Keep awake"); checked: Idle.inhibit; onClicked: Idle.toggleInhibit() }
            }
        }
    }

    ContentSection {
        icon: "space_dashboard"
        title: Translation.tr("At a glance")
        description: Translation.tr("Current devices and the settings you use most")

        ConfigRow {
            preferredColumns: 3
            collapseWidth: 700
            uniform: true

            HomeStatusButton {
                iconName: Network.wifi && Network.wifiEnabled
                    ? (Network.wifiStatus === "connected" ? "wifi" : "signal_wifi_bad")
                    : Network.ethernet
                        ? "lan"
                        : Network.wifiEnabled ? "wifi_find" : "wifi_off"
                label: Translation.tr("Network")
                value: Network.wifi && Network.wifiEnabled
                    ? (Network.networkName || Translation.tr("Connected"))
                    : Network.ethernet
                        ? Translation.tr("Ethernet connected")
                        : Network.wifiEnabled ? Translation.tr("Not connected") : Translation.tr("Off")
                onClicked: root.navigate(1, 0, "networks")
            }

            HomeStatusButton {
                iconName: BluetoothStatus.connected ? "bluetooth_connected"
                    : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                label: Translation.tr("Bluetooth")
                value: BluetoothStatus.connected
                    ? (BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Connected"))
                    : BluetoothStatus.enabled ? Translation.tr("Ready") : Translation.tr("Off")
                onClicked: root.navigate(1, 1, "devices")
            }

            HomeStatusButton {
                iconName: Audio.muted ? "volume_off" : "volume_up"
                label: Translation.tr("Audio")
                value: Audio.currentSinkDisplayName
                onClicked: root.navigate(4)
            }
        }
    }

    ContentSection {
        icon: "apps"
        title: Translation.tr("Common settings")

        GridLayout {
            Layout.fillWidth: true
            columns: width < 600 ? 1 : 2
            columnSpacing: 8
            rowSpacing: 8
            uniformCellWidths: true

            HomeCategoryButton {
                iconName: "mouse"
                label: Translation.tr("Peripherals")
                detail: Translation.tr("Mouse, touchpad and keyboard")
                onClicked: root.navigate(2)
            }

            HomeCategoryButton {
                iconName: "desktop_windows"
                label: Translation.tr("Display")
                detail: Translation.tr("Monitors, brightness and power")
                onClicked: root.navigate(3)
            }

            HomeCategoryButton {
                iconName: "palette"
                label: Translation.tr("Personalisation")
                detail: Translation.tr("Theme, wallpaper and interface")
                onClicked: root.navigate(5)
            }

            HomeCategoryButton {
                iconName: "accessibility_new"
                label: Translation.tr("Accessibility")
                detail: Translation.tr("Sizing, readability and motion")
                onClicked: root.navigate(8)
            }

            HomeCategoryButton {
                iconName: "system_update"
                label: Translation.tr("System update")
                detail: Translation.tr("Updates and system information")
                onClicked: root.navigate(10)
            }

            HomeCategoryButton {
                iconName: "deployed_code"
                label: Translation.tr("Hyprland")
                detail: Translation.tr("Keybinds, rules and configuration")
                onClicked: root.navigate(12)
            }
        }
    }

    // ── Audio ─────────────────────────────────────────────────────────────
    ContentSection {
        visible: false
        icon: "volume_up"
        title: Translation.tr("Audio output")

        StyledComboBox {
            Layout.fillWidth: true
            buttonIcon: "speaker"
            textRole: "displayName"
            model: root.realOutputDevices.map(d => ({ displayName: Audio.friendlyDeviceName(d) }))
            currentIndex: Math.max(0, root.realOutputDevices.findIndex(d => Audio.isCurrentDefaultSink(d)))
            onActivated: index => Audio.setDefaultSink(root.realOutputDevices[index])
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                buttonRadius: Appearance.rounding.full
                implicitWidth: 40; implicitHeight: 40
                onClicked: Audio.toggleMute()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
            }

            StyledSlider {
                Layout.fillWidth: true
                from: 0; to: 1.54
                value: Audio.value
                configuration: StyledSlider.Configuration.M
                usePercentTooltip: false
                tooltipContent: `${Math.round(value * 100)}%`
                onMoved: Audio.setVolume(value)
            }

            StyledText {
                text: `${Math.round(Audio.value * 100)}%`
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    // ── Wi-Fi ─────────────────────────────────────────────────────────────
    ContentSection {
        visible: false
        icon: Network.wifiEnabled ? "wifi" : "wifi_off"
        title: Translation.tr("Wi-Fi")

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: Network.wifiEnabled ? "wifi" : "wifi_off"
                text: Network.wifiEnabled
                    ? (Network.wifi
                        ? Translation.tr("Connected")
                        : Network.wifiStatus === "connecting"
                            ? Translation.tr("Connecting…")
                            : Translation.tr("On, searching"))
                    : Translation.tr("Off")
                checked: Network.wifiEnabled
                onClicked: Network.toggleWifi()
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: Network.wifiScanning ? "radar" : "refresh"
                mainText: Network.wifiScanning ? Translation.tr("Scanning…") : Translation.tr("Scan networks")
                enabled: !Network.wifiScanning && Network.wifiEnabled
                onClicked: Network.rescanWifi()
            }
        }

        Rectangle {
            visible: Network.active !== null && Network.wifi
            Layout.fillWidth: true
            implicitHeight: connRow.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSecondaryContainer

            RowLayout {
                id: connRow
                anchors { fill: parent; margins: 8 }
                spacing: 8
                MaterialSymbol {
                    text: "check_circle"
                    iconSize: 20
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Network.networkName + (Network.networkStrength > 0 ? " • " + Network.networkStrength + "%" : "")
                    color: Appearance.colors.colOnSecondaryContainer
                    font.weight: Font.Medium
                }
                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 90
                    implicitHeight: 28
                    colBackground: Appearance.colors.colLayer2
                    onClicked: Network.disconnectWifiNetwork()
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Disconnect")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }

        Repeater {
            model: Network.friendlyWifiNetworks
            delegate: Rectangle {
                id: netItem
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: netCol.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: modelData.active
                    ? Appearance.colors.colPrimaryContainer
                    : netHover.containsMouse
                        ? Appearance.colors.colLayer1Hover
                        : Appearance.colors.colLayer1

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                ColumnLayout {
                    id: netCol
                    anchors { fill: parent; margins: 8 }
                    spacing: 4

                    RowLayout {
                        spacing: 8
                        MaterialSymbol {
                            property int s: netItem.modelData?.strength ?? 0
                            text: s > 80 ? "signal_wifi_4_bar"
                                : s > 60 ? "network_wifi_3_bar"
                                : s > 40 ? "network_wifi_2_bar"
                                : s > 20 ? "network_wifi_1_bar"
                                : "signal_wifi_0_bar"
                            iconSize: 20
                            color: netItem.modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: netItem.modelData?.ssid ?? Translation.tr("Unknown")
                            color: netItem.modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                            font.weight: netItem.modelData.active ? Font.Medium : Font.Normal
                            elide: Text.ElideRight
                        }
                        StyledText {
                            visible: netItem.modelData?.strength > 0
                            text: netItem.modelData?.strength + "%"
                            color: netItem.modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                        MaterialSymbol {
                            visible: !!(netItem.modelData?.isSecure || netItem.modelData?.active)
                            text: netItem.modelData?.active ? "check" : "lock"
                            iconSize: 16
                            color: netItem.modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }

                    ColumnLayout {
                        visible: netItem.modelData?.askingPassword ?? false
                        Layout.fillWidth: true
                        spacing: 4
                        MaterialTextField {
                            id: pwField
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Password")
                            echoMode: TextInput.Password
                            inputMethodHints: Qt.ImhSensitiveData
                            onAccepted: Network.changePassword(netItem.modelData, pwField.text)
                        }
                        RowLayout {
                            Item { Layout.fillWidth: true }
                            DialogButton {
                                buttonText: Translation.tr("Cancel")
                                onClicked: netItem.modelData.askingPassword = false
                            }
                            DialogButton {
                                buttonText: Translation.tr("Connect")
                                onClicked: Network.changePassword(netItem.modelData, pwField.text)
                            }
                        }
                    }
                }

                MouseArea {
                    id: netHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    visible: !(netItem.modelData?.askingPassword ?? false)
                    onClicked: Network.connectToWifiNetwork(netItem.modelData)
                }
            }
        }

        StyledText {
            visible: !Network.wifiEnabled || Network.friendlyWifiNetworks.length === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: !Network.wifiEnabled ? Translation.tr("Enable Wi-Fi to see networks") : Translation.tr("No networks found — press scan")
            color: Appearance.colors.colSubtext
        }
    }

    // ── Bluetooth ──────────────────────────────────────────────────────────
    ContentSection {
        visible: false
        icon: BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
        title: Translation.tr("Bluetooth")

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: BluetoothStatus.connected ? "bluetooth_connected"
                    : BluetoothStatus.enabled ? "bluetooth"
                    : "bluetooth_disabled"
                text: BluetoothStatus.connected
                    ? Translation.tr("Connected: %1").arg(BluetoothStatus.firstActiveDevice?.name ?? "")
                    : BluetoothStatus.enabled ? Translation.tr("On, not connected") : Translation.tr("Off")
                checked: BluetoothStatus.enabled
                onClicked: {
                    if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "search"
                mainText: (Bluetooth.defaultAdapter?.discovering ?? false) ? Translation.tr("Scanning…") : Translation.tr("Scan devices")
                enabled: BluetoothStatus.enabled
                onClicked: {
                    if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.discovering = !Bluetooth.defaultAdapter.discovering
                }
            }
        }

        Repeater {
            model: ScriptModel {
                values: BluetoothStatus.friendlyDeviceList ?? []
            }
            delegate: Rectangle {
                id: btItem
                required property BluetoothDevice modelData
                Layout.fillWidth: true
                implicitHeight: btRow.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: modelData.connected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                RowLayout {
                    id: btRow
                    anchors { fill: parent; margins: 8 }
                    spacing: 8

                    MaterialSymbol {
                        text: modelData.connected ? "bluetooth_connected" : "bluetooth"
                        iconSize: 20
                        color: modelData.connected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            text: modelData.name || Translation.tr("Unknown device")
                            color: modelData.connected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                            font.weight: modelData.connected ? Font.Medium : Font.Normal
                        }
                        StyledText {
                            visible: modelData.paired
                            text: {
                                let s = modelData.connected ? Translation.tr("Connected") : Translation.tr("Paired")
                                if (modelData.batteryAvailable) s += " • " + Math.round(modelData.battery * 100) + "%"
                                return s
                            }
                            color: modelData.connected ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }

                    RippleButton {
                        visible: modelData.paired
                        buttonRadius: Appearance.rounding.full
                        implicitWidth: 90
                        implicitHeight: 28
                        colBackground: modelData.connected ? Appearance.colors.colLayer2 : Appearance.colors.colPrimary
                        onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: btItem.modelData.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                            color: btItem.modelData.connected ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnPrimary
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }
        }

        StyledText {
            visible: !BluetoothStatus.enabled
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Enable Bluetooth to see devices")
            color: Appearance.colors.colSubtext
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "settings_bluetooth"
            mainText: Translation.tr("Open full Bluetooth settings")
            onClicked: Quickshell.execDetached(["bash", "-c", Config.options.apps.bluetooth])
        }
    }

    // ── Network tools ──────────────────────────────────────────────────────
    ContentSection {
        visible: false
        icon: "lan"
        title: Translation.tr("Network tools")

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "settings_ethernet"
                mainText: Translation.tr("Ethernet settings")
                onClicked: Quickshell.execDetached(["bash", "-c", Config.options.apps.networkEthernet])
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "open_in_browser"
                mainText: Translation.tr("Portal / captive login")
                onClicked: Network.openPublicWifiPortal()
            }
        }
    }

    component HomeStatusButton: RippleButton {
        id: statusButton
        required property string iconName
        required property string label
        required property string value

        Layout.fillWidth: true
        implicitHeight: 72
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colLayer1Hover

        contentItem: RowLayout {
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: Appearance.rounding.small
                color: Appearance.colors.colSecondaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: statusButton.iconName
                    iconSize: 20
                    fill: 1
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: statusButton.label
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: statusButton.value
                    color: Appearance.colors.colOnLayer1
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }

            MaterialSymbol {
                text: "chevron_right"
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
        }
    }

    component HomeCategoryButton: RippleButton {
        id: categoryButton
        required property string iconName
        required property string label
        required property string detail

        Layout.fillWidth: true
        implicitHeight: 58
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colLayer1Hover

        contentItem: RowLayout {
            spacing: 10

            MaterialSymbol {
                text: categoryButton.iconName
                iconSize: 21
                fill: 1
                color: Appearance.colors.colOnSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: categoryButton.label
                    color: Appearance.colors.colOnLayer1
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: categoryButton.detail
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
            }

            MaterialSymbol {
                text: "chevron_right"
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
        }
    }

    component DashboardPanel: Rectangle {
        id: dashboardPanel
        required property string title
        required property string iconName
        default property alias panelContent: panelColumn.data

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: panelColumn.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        ColumnLayout {
            id: panelColumn
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                MaterialSymbol { text: dashboardPanel.iconName; iconSize: 20; color: Appearance.colors.colPrimary }
                StyledText { Layout.fillWidth: true; text: dashboardPanel.title; color: Appearance.colors.colOnLayer1; font.weight: Font.DemiBold }
            }
        }
    }

}
