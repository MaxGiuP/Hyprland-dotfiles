import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.wifiNetworks
import qs.modules.ii.sidebarRight.bluetoothDevices
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

StyledPopup {
    id: root

    keepOpenOnPopupHover: true
    horizontalOffset: -8
    property real contentWidth: 390
    property real maxListHeight: 180

    Component.onCompleted: {
        if (Network.wifiEnabled && !Network.wifiScanning)
            Network.rescanWifi();
    }

    ColumnLayout {
        anchors.centerIn: parent
        implicitWidth: root.contentWidth
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialSymbol {
                text: Network.materialSymbol
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Translation.tr("Connect to Wi-Fi")
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Network.ethernet
                        ? Translation.tr("Ethernet")
                        : Network.networkName.length > 0
                            ? Network.networkName
                            : Network.wifiEnabled
                                ? Translation.tr("Disconnected")
                                : Translation.tr("Wi-Fi off")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
            }

            RippleButton {
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                toggled: Network.wifiEnabled
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                onClicked: Network.toggleWifi()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: Network.wifiEnabled ? "wifi" : "wifi_off"
                    iconSize: 20
                    color: Network.wifiEnabled
                        ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        StyledIndeterminateProgressBar {
            visible: Network.wifiScanning
            Layout.fillWidth: true
        }

        ListView {
            id: wifiList
            visible: Network.wifiEnabled && count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Math.min(contentHeight, root.maxListHeight) : 0
            clip: true
            spacing: 0

            model: ScriptModel {
                values: Network.friendlyWifiNetworks.slice(0, 5)
            }

            delegate: WifiNetworkItem {
                required property WifiAccessPoint modelData
                wifiNetwork: modelData
                width: ListView.view.width
            }

            ScrollBar.vertical: ScrollBar {}
        }

        StyledText {
            visible: !Network.wifiEnabled || wifiList.count === 0
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.topMargin: 6
            Layout.bottomMargin: 8
            text: Network.wifiEnabled
                ? Translation.tr("No networks")
                : Translation.tr("Wi-Fi off")
            color: Appearance.colors.colSubtext
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialSymbol {
                text: BluetoothStatus.connected
                    ? "bluetooth_connected"
                    : BluetoothStatus.enabled
                        ? "bluetooth"
                        : "bluetooth_disabled"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Translation.tr("Bluetooth devices")
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: BluetoothStatus.connected
                        ? (BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Connected"))
                        : BluetoothStatus.enabled
                            ? Translation.tr("Bluetooth on")
                            : Translation.tr("Bluetooth off")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
            }

            RippleButton {
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                enabled: BluetoothStatus.available
                toggled: BluetoothStatus.enabled
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                onClicked: {
                    if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                    iconSize: 20
                    color: BluetoothStatus.enabled
                        ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        ListView {
            id: bluetoothList
            visible: BluetoothStatus.enabled && count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Math.min(contentHeight, root.maxListHeight) : 0
            clip: true
            spacing: 0

            model: ScriptModel {
                values: BluetoothStatus.friendlyDeviceList.slice(0, 5)
            }

            delegate: BluetoothDeviceItem {
                required property var modelData
                device: modelData
                width: ListView.view.width
            }

            ScrollBar.vertical: ScrollBar {}
        }

        StyledText {
            visible: !BluetoothStatus.enabled || bluetoothList.count === 0
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            Layout.topMargin: 6
            Layout.bottomMargin: 8
            text: BluetoothStatus.enabled
                ? Translation.tr("No devices")
                : Translation.tr("Bluetooth off")
            color: Appearance.colors.colSubtext
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            DialogButton {
                Layout.fillWidth: true
                buttonText: Translation.tr("Wi-Fi")
                onClicked: {
                    root.hoverHeld = false;
                    Quickshell.execDetached(["bash", "-lc", Config.options.apps.network]);
                }
            }

            DialogButton {
                Layout.fillWidth: true
                buttonText: Translation.tr("Bluetooth devices")
                onClicked: {
                    root.hoverHeld = false;
                    Quickshell.execDetached(["bash", "-lc", Config.options.apps.bluetooth]);
                }
            }
        }
    }
}
