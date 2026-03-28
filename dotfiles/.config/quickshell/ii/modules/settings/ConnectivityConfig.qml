import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760

    // ── Wi-Fi ────────────────────────────────────────────────────────────────
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
                mainText: Network.wifiScanning
                    ? Translation.tr("Scanning…")
                    : Translation.tr("Scan networks")
                enabled: !Network.wifiScanning && Network.wifiEnabled
                onClicked: Network.rescanWifi()
            }
        }

        // Connected network banner
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

        // Available networks list
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
                            color: netItem.modelData.active
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: netItem.modelData?.ssid ?? Translation.tr("Unknown")
                            color: netItem.modelData.active
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnLayer1
                            font.weight: netItem.modelData.active ? Font.Medium : Font.Normal
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: netItem.modelData?.strength > 0
                            text: netItem.modelData?.strength + "%"
                            color: netItem.modelData.active
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }

                        MaterialSymbol {
                            visible: !!(netItem.modelData?.isSecure || netItem.modelData?.active)
                            text: netItem.modelData?.active ? "check" : "lock"
                            iconSize: 16
                            color: netItem.modelData.active
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colSubtext
                        }
                    }

                    // Password prompt
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

        // No networks placeholder
        StyledText {
            visible: !Network.wifiEnabled || Network.friendlyWifiNetworks.length === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: !Network.wifiEnabled
                ? Translation.tr("Enable Wi-Fi to see networks")
                : Translation.tr("No networks found — press scan")
            color: Appearance.colors.colSubtext
        }
    }

    // ── Bluetooth ─────────────────────────────────────────────────────────────
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
                    : BluetoothStatus.enabled
                        ? Translation.tr("On, not connected")
                        : Translation.tr("Off")
                checked: BluetoothStatus.enabled
                onClicked: {
                    if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "search"
                mainText: (Bluetooth.defaultAdapter?.discovering ?? false)
                    ? Translation.tr("Scanning…")
                    : Translation.tr("Scan devices")
                enabled: BluetoothStatus.enabled
                onClicked: {
                    if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.discovering = !Bluetooth.defaultAdapter.discovering
                }
            }
        }

        // Paired / known devices
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
                color: modelData.connected
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colLayer1

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
                        color: modelData.connected
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colOnLayer1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: modelData.name || Translation.tr("Unknown device")
                            color: modelData.connected
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnLayer1
                            font.weight: modelData.connected ? Font.Medium : Font.Normal
                        }

                        StyledText {
                            visible: modelData.paired
                            text: {
                                let s = modelData.connected ? Translation.tr("Connected") : Translation.tr("Paired");
                                if (modelData.batteryAvailable)
                                    s += " • " + Math.round(modelData.battery * 100) + "%";
                                return s;
                            }
                            color: modelData.connected
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }

                    RippleButton {
                        visible: modelData.paired
                        buttonRadius: Appearance.rounding.full
                        implicitWidth: 90
                        implicitHeight: 28
                        colBackground: modelData.connected
                            ? Appearance.colors.colLayer2
                            : Appearance.colors.colPrimary
                        onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: btItem.modelData.connected
                                ? Translation.tr("Disconnect")
                                : Translation.tr("Connect")
                            color: btItem.modelData.connected
                                ? Appearance.colors.colOnLayer1
                                : Appearance.colors.colOnPrimary
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

    // ── Network tools ─────────────────────────────────────────────────────────
    ContentSection {
        icon: "lan"
        title: Translation.tr("Network tools")

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "settings_ethernet"
                mainText: Translation.tr("Network settings")
                onClicked: Quickshell.execDetached(["bash", "-c", Config.options.apps.network])
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
