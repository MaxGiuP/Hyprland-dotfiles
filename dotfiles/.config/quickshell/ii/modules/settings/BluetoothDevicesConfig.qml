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

    PwObjectTracker {
        objects: root.trackedOutputDevices
    }

    ContentSection {
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
        icon: "bluetooth"
        title: Translation.tr("Bluetooth devices")

        Repeater {
            model: BluetoothStatus.friendlyDeviceList

            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: deviceRow.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                RowLayout {
                    id: deviceRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    MaterialSymbol {
                        text: modelData.connected ? "bluetooth_connected" : modelData.paired ? "headphones" : "bluetooth_searching"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: modelData.name || Translation.tr("Unknown device")
                            color: Appearance.colors.colOnLayer1
                            font.weight: Font.Medium
                        }

                        StyledText {
                            text: modelData.connected
                                ? Translation.tr("Connected")
                                : modelData.paired
                                    ? Translation.tr("Paired")
                                    : Translation.tr("Available")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }
        }

        StyledText {
            visible: BluetoothStatus.friendlyDeviceList.length === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("No Bluetooth devices are currently visible.")
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
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
