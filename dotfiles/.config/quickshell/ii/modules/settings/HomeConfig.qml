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

}
