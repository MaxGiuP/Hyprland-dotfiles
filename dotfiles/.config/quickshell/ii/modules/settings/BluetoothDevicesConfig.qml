import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760

    readonly property var trackedOutputDevices: Audio.outputDevices.filter(d => d.name !== "qs_mono_out")
    readonly property var realOutputDevices: Audio.selectableOutputDevices.filter(d => d.name !== "qs_mono_out")
    readonly property bool isDiscovering: Bluetooth.defaultAdapter?.discovering ?? false

    function scrollToSection(sectionId) {
        const map = { "overview": btOverviewSection, "devices": btDevicesSection, "other": btOtherSection }
        const target = map[sectionId]
        if (target) root.contentY = Math.max(0, target.y - 10)
    }

    PwObjectTracker {
        objects: root.trackedOutputDevices
    }

    Timer {
        id: scanTimer
        interval: 30000
        onTriggered: {
            if (Bluetooth.defaultAdapter?.discovering)
                Bluetooth.defaultAdapter.discovering = false
        }
    }

    ContentSection {
        id: btOverviewSection
        icon: "devices"
        title: Translation.tr("Bluetooth & devices")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Manage the hardware around your desktop: Bluetooth accessories, audio devices, displays, and the shell surfaces that react to them.")
        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                text: BluetoothStatus.connected
                    ? (BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Bluetooth connected"))
                    : BluetoothStatus.enabled
                        ? Translation.tr("Bluetooth on")
                        : Translation.tr("Bluetooth off")
                checked: BluetoothStatus.enabled
                enabled: BluetoothStatus.available
                onClicked: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
            }

            StyledComboBox {
                Layout.fillWidth: true
                buttonIcon: "speaker"
                textRole: "displayName"
                model: root.realOutputDevices.map(d => ({ displayName: Audio.friendlyDeviceName(d) }))
                currentIndex: Math.max(0, root.realOutputDevices.findIndex(d => Audio.isCurrentDefaultSink(d)))
                onActivated: index => Audio.setDefaultSink(root.realOutputDevices[index])
            }
        }
    }

    ContentSection {
        id: btDevicesSection
        icon: "bluetooth"
        title: Translation.tr("Bluetooth devices")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: root.isDiscovering ? "stop_circle" : "bluetooth_searching"
                mainText: root.isDiscovering ? Translation.tr("Stop scanning") : Translation.tr("Scan for devices")
                enabled: BluetoothStatus.enabled && BluetoothStatus.available
                toggled: root.isDiscovering
                onClicked: {
                    if (!Bluetooth.defaultAdapter) return
                    if (root.isDiscovering) {
                        Bluetooth.defaultAdapter.discovering = false
                        scanTimer.stop()
                    } else {
                        Bluetooth.defaultAdapter.discovering = true
                        scanTimer.restart()
                    }
                }
            }
        }

        StyledIndeterminateProgressBar {
            Layout.fillWidth: true
            visible: root.isDiscovering
        }

        Repeater {
            model: BluetoothStatus.friendlyDeviceList

            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: deviceRow.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: modelData.connected
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOutlineVariant

                RowLayout {
                    id: deviceRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12

                    Item {
                        implicitWidth: 32
                        implicitHeight: 32

                        Image {
                            id: deviceSystemIcon
                            anchors.fill: parent
                            source: modelData.icon ? Quickshell.iconPath(modelData.icon, "") : ""
                            visible: status === Image.Ready
                            fillMode: Image.PreserveAspectFit
                        }

                        MaterialSymbol {
                            anchors.fill: parent
                            visible: !deviceSystemIcon.visible
                            text: {
                                if (modelData.connected) return "bluetooth_connected"
                                if (modelData.pairing) return "bluetooth_searching"
                                if (modelData.paired) return "headphones"
                                return "bluetooth_searching"
                            }
                            iconSize: 24
                            color: modelData.connected
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnLayer1
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: modelData.name || Translation.tr("Unknown device")
                            color: Appearance.colors.colOnLayer1
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: 6
                            Layout.fillWidth: true

                            StyledText {
                                text: {
                                    const s = modelData.state
                                    if (s === BluetoothDeviceState.Connecting) return Translation.tr("Connecting…")
                                    if (s === BluetoothDeviceState.Disconnecting) return Translation.tr("Disconnecting…")
                                    if (modelData.connected) return Translation.tr("Connected")
                                    if (modelData.pairing) return Translation.tr("Pairing…")
                                    if (modelData.paired) return Translation.tr("Paired")
                                    return Translation.tr("Available")
                                }
                                color: modelData.connected
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            RowLayout {
                                visible: modelData.batteryAvailable
                                spacing: 3

                                MaterialSymbol {
                                    text: {
                                        const p = modelData.battery
                                        if (p > 0.9) return "battery_full"
                                        if (p > 0.72) return "battery_6_bar"
                                        if (p > 0.54) return "battery_5_bar"
                                        if (p > 0.36) return "battery_3_bar"
                                        if (p > 0.18) return "battery_2_bar"
                                        if (p > 0.05) return "battery_1_bar"
                                        return "battery_0_bar"
                                    }
                                    iconSize: Appearance.font.pixelSize.small + 2
                                    color: modelData.battery < 0.2
                                        ? Appearance.colors.colError
                                        : Appearance.colors.colSubtext
                                }

                                StyledText {
                                    text: Math.round(modelData.battery * 100) + "%"
                                    color: modelData.battery < 0.2
                                        ? Appearance.colors.colError
                                        : Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }
                        }
                    }

                    RowLayout {
                        spacing: 4

                        RippleButtonWithIcon {
                            visible: modelData.connected || (modelData.paired && !modelData.pairing)
                            enabled: modelData.state !== BluetoothDeviceState.Connecting
                                  && modelData.state !== BluetoothDeviceState.Disconnecting
                            materialIcon: modelData.connected ? "link_off" : "link"
                            mainText: {
                                if (modelData.state === BluetoothDeviceState.Connecting) return Translation.tr("Connecting…")
                                if (modelData.state === BluetoothDeviceState.Disconnecting) return Translation.tr("Disconnecting…")
                                return modelData.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                            }
                            onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                        }

                        RippleButtonWithIcon {
                            visible: !modelData.connected
                            materialIcon: modelData.pairing ? "cancel" : modelData.paired ? "delete" : "add_link"
                            mainText: modelData.pairing
                                ? Translation.tr("Cancel")
                                : modelData.paired
                                    ? Translation.tr("Forget")
                                    : Translation.tr("Pair")
                            onClicked: {
                                if (modelData.pairing) modelData.cancelPair()
                                else if (modelData.paired) modelData.forget()
                                else modelData.pair()
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            visible: BluetoothStatus.friendlyDeviceList.length === 0 && !root.isDiscovering
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: BluetoothStatus.enabled
                ? Translation.tr("No Bluetooth devices found. Tap \"Scan for devices\" to search.")
                : Translation.tr("Enable Bluetooth to see devices.")
            color: Appearance.colors.colSubtext
        }

        StyledText {
            visible: BluetoothStatus.friendlyDeviceList.length === 0 && root.isDiscovering
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Scanning for nearby devices…")
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        id: btOtherSection
        icon: "desktop_windows"
        title: Translation.tr("Other devices")

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "display_settings"
                mainText: Translation.tr("Open system settings")
                onClicked: Quickshell.execDetached(["systemsettings"])
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "tune"
                mainText: Translation.tr("Audio mixer")
                onClicked: Quickshell.execDetached(["bash", "-lc", Config.options.apps.volumeMixer])
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "settings_bluetooth"
                mainText: Translation.tr("Open Bluetooth app")
                onClicked: Quickshell.execDetached(["bash", "-lc", Config.options.apps.bluetooth])
            }
        }
    }
}
