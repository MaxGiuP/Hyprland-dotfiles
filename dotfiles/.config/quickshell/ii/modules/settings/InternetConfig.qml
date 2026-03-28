import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760

    ContentSection {
        icon: Network.wifiEnabled ? "wifi" : "wifi_off"
        title: Translation.tr("Internet")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("See your current connection state, scan nearby networks, and jump into your system networking tools.")
        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: Network.materialSymbol
                text: Network.ethernet
                    ? Translation.tr("Ethernet connected")
                    : Network.wifi
                        ? `${Network.networkName || Translation.tr("Wi-Fi connected")}`
                        : Network.wifiEnabled
                            ? Translation.tr("Wi-Fi on")
                            : Translation.tr("Wi-Fi off")
                checked: Network.wifiEnabled
                onClicked: Network.toggleWifi()
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: Network.wifiScanning ? "radar" : "refresh"
                mainText: Network.wifiScanning ? Translation.tr("Scanning…") : Translation.tr("Scan Wi-Fi")
                enabled: !Network.wifiScanning && Network.wifiEnabled
                onClicked: Network.rescanWifi()
            }
        }
    }

    ContentSection {
        icon: "network_wifi"
        title: Translation.tr("Nearby networks")

        Repeater {
            model: Network.friendlyWifiNetworks.slice(0, 8)

            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: netRow.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: modelData.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                RowLayout {
                    id: netRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    MaterialSymbol {
                        text: modelData.active ? "check_circle" : modelData.isSecure ? "lock" : "wifi"
                        iconSize: 18
                        color: modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: `${modelData.ssid || Translation.tr("Unknown")} ${modelData.strength > 0 ? `• ${modelData.strength}%` : ""}`
                        color: modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        StyledText {
            visible: !Network.wifiEnabled || Network.friendlyWifiNetworks.length === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: !Network.wifiEnabled ? Translation.tr("Enable Wi-Fi to see networks.") : Translation.tr("No networks found right now.")
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        icon: "settings_ethernet"
        title: Translation.tr("Network tools")

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "wifi"
                mainText: Translation.tr("Open network settings")
                onClicked: Quickshell.execDetached(["bash", "-lc", Config.options.apps.network])
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "lan"
                mainText: Translation.tr("Open ethernet settings")
                onClicked: Quickshell.execDetached(["bash", "-lc", Config.options.apps.networkEthernet])
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "language"
                mainText: Translation.tr("Open captive portal test")
                onClicked: Network.openPublicWifiPortal()
            }
        }
    }
}
