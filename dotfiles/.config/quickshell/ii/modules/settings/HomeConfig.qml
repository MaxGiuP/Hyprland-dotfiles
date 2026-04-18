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

    PwObjectTracker {
        objects: root.trackedOutputDevices
    }

    // ── Search index ──────────────────────────────────────────────────────
    // Page map (after Bluetooth+Internet merged into Connectivity at index 1):
    // 0:Home  1:Connectivity  2:Display  3:Audio  4:Customisation
    // 5:Interface  6:Account  7:DateTime  8:Accessibility
    // 9:Security  10:SystemInfo  11:Services  12:Hyprland
    readonly property var searchIndex: [
        // 4 · Customisation
        { label: "Wallpaper & Colors", page: 4, icon: "tune" },
        { label: "Color palette style", page: 4, icon: "tune" },
        { label: "Transparency", page: 4, icon: "tune" },
        { label: "Bar position", page: 4, icon: "tune" },
        { label: "Bar style", page: 4, icon: "tune" },
        { label: "Bar transparency", page: 4, icon: "tune" },
        { label: "Screen rounded corners", page: 4, icon: "tune" },
        { label: "GTK theme", page: 4, icon: "palette" },
        { label: "Icon theme", page: 4, icon: "palette" },
        { label: "Cursor theme", page: 4, icon: "palette" },
        { label: "Cursor size", page: 4, icon: "palette" },
        { label: "Font family", page: 4, icon: "palette" },
        { label: "Font size", page: 4, icon: "palette" },
        { label: "Change wallpaper", page: 4, icon: "palette" },
        { label: "Dark mode", page: 4, icon: "palette" },
        { label: "Light mode", page: 4, icon: "palette" },
        { label: "Color scheme", page: 4, icon: "palette" },
        { label: "Kvantum theme", page: 4, icon: "palette" },
        { label: "KDE theme", page: 4, icon: "palette" },
        { label: "GNOME interface settings", page: 4, icon: "palette" },
        { label: "GTK 3 settings", page: 4, icon: "palette" },
        { label: "GTK 4 settings", page: 4, icon: "palette" },
        { label: "kdeglobals", page: 4, icon: "palette" },
        { label: "Prefer dark apps", page: 4, icon: "palette" },
        { label: "Text scaling", page: 4, icon: "palette" },
        { label: "Hot corners", page: 4, icon: "palette" },
        { label: "Animations", page: 4, icon: "palette" },
        // 1 · Connectivity → Bluetooth sub-tab
        { label: "Bluetooth devices", page: 1, subTab: 1, sectionId: "devices", icon: "bluetooth" },
        { label: "Pair device", page: 1, subTab: 1, sectionId: "devices", icon: "bluetooth" },
        { label: "Audio output device", page: 1, subTab: 1, sectionId: "overview", icon: "bluetooth" },
        { label: "Open Bluetooth app", page: 1, subTab: 1, sectionId: "other", icon: "bluetooth" },
        // 2 · Display
        { label: "Night light", page: 2, icon: "desktop_windows" },
        { label: "Color temperature", page: 2, icon: "desktop_windows" },
        { label: "Night light schedule", page: 2, icon: "desktop_windows" },
        { label: "Anti-flashbang", page: 2, icon: "desktop_windows" },
        { label: "Low battery threshold", page: 2, icon: "desktop_windows" },
        { label: "Critical battery threshold", page: 2, icon: "desktop_windows" },
        { label: "Automatic suspend on low battery", page: 2, icon: "desktop_windows" },
        { label: "Monitor positions", page: 2, icon: "desktop_windows" },
        { label: "Brightness", page: 2, icon: "desktop_windows" },
        // 3 · Audio
        { label: "Default output device", page: 3, icon: "volume_up" },
        { label: "Default input device", page: 3, icon: "volume_up" },
        { label: "Mono output", page: 3, icon: "volume_up" },
        { label: "App streams", page: 3, icon: "volume_up" },
        { label: "Earbang protection", page: 3, icon: "volume_up" },
        { label: "Volume ceiling", page: 3, icon: "volume_up" },
        { label: "Max volume increase per step", page: 3, icon: "volume_up" },
        { label: "System sounds", page: 3, icon: "volume_up" },
        { label: "Battery alert sound", page: 3, icon: "volume_up" },
        { label: "Microphone input", page: 3, icon: "volume_up" },
        // 1 · Connectivity → Internet sub-tab
        { label: "Wi-Fi networks", page: 1, subTab: 0, sectionId: "internet", icon: "language" },
        { label: "Scan Wi-Fi", page: 1, subTab: 0, sectionId: "networks", icon: "language" },
        { label: "Ethernet", page: 1, subTab: 0, sectionId: "internet", icon: "language" },
        { label: "Network settings", page: 1, subTab: 0, sectionId: "extra", icon: "language" },
        { label: "Captive portal", page: 1, subTab: 0, sectionId: "extra", icon: "language" },
        // 5 · Interface & Apps
        { label: "Dock", page: 5, icon: "preview" },
        { label: "Dock pinned apps", page: 5, icon: "preview" },
        { label: "Lock screen", page: 5, icon: "preview" },
        { label: "Auto-lock delay", page: 5, icon: "preview" },
        { label: "Lock screen style", page: 5, icon: "preview" },
        { label: "Require password to power off", page: 5, icon: "preview" },
        { label: "Notifications timeout", page: 5, icon: "preview" },
        { label: "Crosshair overlay", page: 5, icon: "preview" },
        { label: "Floating image overlay", page: 5, icon: "preview" },
        { label: "Overview layout", page: 5, icon: "preview" },
        { label: "Corner open sidebar", page: 5, icon: "preview" },
        { label: "Quick toggles layout", page: 5, icon: "preview" },
        { label: "Main font", page: 5, icon: "preview" },
        { label: "Monospace font", page: 5, icon: "preview" },
        { label: "Numbers font", page: 5, icon: "preview" },
        { label: "Cheat sheet super key symbol", page: 5, icon: "preview" },
        { label: "On-screen display timeout", page: 5, icon: "preview" },
        { label: "Region selector / screen snip", page: 5, icon: "preview" },
        { label: "Wallpaper file picker", page: 5, icon: "preview" },
        { label: "Translator sidebar", page: 5, icon: "preview" },
        { label: "Bluetooth app command", page: 5, icon: "apps" },
        { label: "Network settings command", page: 5, icon: "apps" },
        { label: "Terminal command", page: 5, icon: "apps" },
        { label: "System update command", page: 5, icon: "apps" },
        { label: "Volume mixer command", page: 5, icon: "apps" },
        { label: "Task manager command", page: 5, icon: "apps" },
        { label: "Change password command", page: 5, icon: "apps" },
        { label: "Launcher pinned apps", page: 5, icon: "apps" },
        // 6 · Account
        { label: "Manage users", page: 6, icon: "person" },
        { label: "Change password", page: 6, icon: "person" },
        // 7 · Date, time & language
        { label: "Language / locale", page: 7, icon: "schedule" },
        { label: "System locale", page: 7, icon: "schedule" },
        { label: "Generate translation", page: 7, icon: "schedule" },
        { label: "Clock format 24h 12h", page: 7, icon: "schedule" },
        { label: "Second precision clock", page: 7, icon: "schedule" },
        { label: "Translation map", page: 7, icon: "schedule" },
        // 8 · Accessibility
        { label: "Cursor size", page: 8, icon: "accessibility_new" },
        { label: "Text scaling accessibility", page: 8, icon: "accessibility_new" },
        { label: "Disable animations", page: 8, icon: "accessibility_new" },
        { label: "Readability", page: 8, icon: "accessibility_new" },
        // 9 · Security & privacy
        { label: "AI policy", page: 9, icon: "shield_lock" },
        { label: "Clipboard privacy", page: 9, icon: "shield_lock" },
        { label: "Wallpaper privacy", page: 9, icon: "shield_lock" },
        // 10 · System info & update
        { label: "Check for updates", page: 10, icon: "system_update" },
        { label: "System information", page: 10, icon: "system_update" },
        { label: "CPU memory GPU info", page: 10, icon: "system_update" },
        // 11 · Services
        { label: "AI system prompt", page: 11, icon: "widgets" },
        { label: "Music recognition timeout", page: 11, icon: "widgets" },
        { label: "User agent", page: 11, icon: "widgets" },
        { label: "Search engine URL", page: 11, icon: "widgets" },
        { label: "Search prefixes", page: 11, icon: "widgets" },
        { label: "Weather city GPS", page: 11, icon: "widgets" },
        { label: "Screenshot save path", page: 11, icon: "widgets" },
        { label: "Video recording path", page: 11, icon: "widgets" },
        // 12 · Hyprland
        { label: "Hyprland config files", page: 12, icon: "deployed_code" },
        { label: "Keybinds", page: 12, icon: "deployed_code" },
        { label: "Window rules", page: 12, icon: "deployed_code" },
        { label: "Workspace bindings", page: 12, icon: "deployed_code" },
        { label: "Monitor overrides", page: 12, icon: "deployed_code" },
        { label: "Environment variables", page: 12, icon: "deployed_code" },
        { label: "Startup commands autostart", page: 12, icon: "deployed_code" },
    ]

    // ── Search ────────────────────────────────────────────────────────────
    ContentSection {
        icon: "search"
        title: Translation.tr("Search settings")

        MaterialTextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Type to search…")
        }

        Repeater {
            model: {
                const q = searchField.text.trim().toLowerCase()
                if (!q) return []
                const host = root.settingsHost ?? Window.window
                const pages = host?.pages ?? []
                const seen = new Set()
                const results = []
                for (const entry of root.searchIndex) {
                    if (entry.label.toLowerCase().includes(q) && !seen.has(entry.label)) {
                        seen.add(entry.label)
                        results.push({
                            icon: entry.icon,
                            label: entry.label,
                            pageName: pages[entry.page]?.displayName ?? "",
                            pageIndex: entry.page,
                            subTab: entry.subTab ?? 0,
                            sectionId: entry.sectionId ?? ""
                        })
                    }
                }
                return results
            }

            delegate: RippleButton {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: resultRow.implicitHeight + 16
                buttonRadius: Appearance.rounding.normal
                onClicked: {
                    const win = root.settingsHost ?? Window.window
                    if (!win)
                        return
                    // Only set subTab nav when there's actually a subtab specified
                    win.requestedSubTab = modelData.subTab !== undefined ? modelData.subTab : -1
                    win.requestedSectionId = modelData.sectionId ?? ""
                    win.currentPage = modelData.pageIndex
                }

                RowLayout {
                    id: resultRow
                    anchors { fill: parent; margins: 8 }
                    spacing: 10

                    MaterialSymbol {
                        text: modelData.icon
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        StyledText {
                            text: modelData.label
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                        StyledText {
                            text: modelData.pageName
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }

                    MaterialSymbol {
                        text: "chevron_right"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }

    // ── Audio ─────────────────────────────────────────────────────────────
    ContentSection {
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

}
