import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760

    // ── Extended connection details ────────────────────────────────────────
    property string wifiDevice: ""
    property string wifiIp: ""
    property string wifiGateway: ""
    property string wifiDns: ""
    property string wifiMac: ""
    property string ethDevice: ""
    property string ethIp: ""
    property string ethGateway: ""
    property string ethDns: ""
    property string ethMac: ""
    property var ifaces: []

    function refreshDetails() {
        if (!detailsProc.running) {
            root.ifaces = []
            detailsProc.running = true
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.refreshDetails()
    }

    Connections {
        target: Network
        function onWifiChanged()       { root.refreshDetails() }
        function onEthernetChanged()   { root.refreshDetails() }
        function onWifiStatusChanged() { root.refreshDetails() }
    }

    Process {
        id: detailsProc
        running: true
        command: ["bash", "-c",
            "nmcli -t -f DEVICE,TYPE,STATE dev 2>/dev/null | grep -v ':loopback:' | " +
            "while IFS=: read -r dev type rest; do echo \"iface:$dev|$type|$rest\"; done; " +
            "for entry in 'wifi:wifi' 'eth:ethernet'; do " +
            "  pfx=${entry%%:*}; nmtype=${entry#*:}; " +
            "  dev=$(nmcli -t -f DEVICE,TYPE dev 2>/dev/null | awk -F: -v t=$nmtype '$2==t{print $1; exit}'); " +
            "  [ -z \"$dev\" ] && continue; " +
            "  echo \"${pfx}_dev:$dev\"; " +
            "  mac=$(nmcli -g GENERAL.HWADDR dev show \"$dev\" 2>/dev/null); " +
            "  [ -n \"$mac\" ] && echo \"${pfx}_mac:$mac\"; " +
            "  ip=$(nmcli -g IP4.ADDRESS dev show \"$dev\" 2>/dev/null | head -1); " +
            "  [ -n \"$ip\" ] && echo \"${pfx}_ip:${ip%%/*}\"; " +
            "  gw=$(nmcli -g IP4.GATEWAY dev show \"$dev\" 2>/dev/null | head -1); " +
            "  [ -n \"$gw\" ] && echo \"${pfx}_gw:$gw\"; " +
            "  dns=$(nmcli -g IP4.DNS dev show \"$dev\" 2>/dev/null | head -3 | tr '\\n' ' '); " +
            "  [ -n \"${dns// /}\" ] && echo \"${pfx}_dns:${dns% }\"; " +
            "done"
        ]
        stdout: SplitParser {
            onRead: data => {
                const colon = data.indexOf(":")
                if (colon < 0) return
                const key = data.slice(0, colon)
                const val = data.slice(colon + 1)
                if (key === "iface") {
                    const parts = val.split("|")
                    if (parts.length >= 3) {
                        const arr = [...root.ifaces]
                        arr.push({ device: parts[0], type: parts[1], state: parts.slice(2).join(" ") })
                        root.ifaces = arr
                    }
                } else switch (key) {
                    case "wifi_dev": root.wifiDevice  = val; break
                    case "wifi_mac": root.wifiMac     = val; break
                    case "wifi_ip":  root.wifiIp      = val; break
                    case "wifi_gw":  root.wifiGateway = val; break
                    case "wifi_dns": root.wifiDns     = val.trim(); break
                    case "eth_dev":  root.ethDevice   = val; break
                    case "eth_mac":  root.ethMac      = val; break
                    case "eth_ip":   root.ethIp       = val; break
                    case "eth_gw":   root.ethGateway  = val; break
                    case "eth_dns":  root.ethDns      = val.trim(); break
                }
            }
        }
    }

    // ── Reusable detail row: white-on-secondary for connected banner ───────
    component ActiveNetRow: RowLayout {
        property string dlabel: ""
        property string dvalue: ""
        property bool   mono:   false
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.preferredWidth: 72
            text: parent.dlabel
            color: Appearance.colors.colOnSecondaryContainer
            font.pixelSize: Appearance.font.pixelSize.smaller
            opacity: 0.75
        }
        StyledText {
            Layout.fillWidth: true
            text: parent.dvalue || "—"
            color: Appearance.colors.colOnSecondaryContainer
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: parent.mono
                ? Appearance.font.family.monospace
                : Appearance.font.family.main
            elide: Text.ElideRight
        }
    }

    // ── Reusable detail row: label/value for Ethernet section ─────────────
    component EthDetailRow: RowLayout {
        property string elabel: ""
        property string evalue: ""
        property bool   mono:   false
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.preferredWidth: 92
            text: parent.elabel
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
        StyledText {
            Layout.fillWidth: true
            text: parent.evalue || "—"
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: parent.mono
                ? Appearance.font.family.monospace
                : Appearance.font.family.main
            elide: Text.ElideRight
        }
    }

    // ── Network Interfaces ─────────────────────────────────────────────────
    ContentSection {
        icon: "router"
        title: Translation.tr("Network Interfaces")

        Repeater {
            model: root.ifaces
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    text: modelData.type === "wifi"     ? "wifi"
                        : modelData.type === "ethernet" ? "lan"
                        : "device_hub"
                    iconSize: 18
                    color: modelData.state.startsWith("connected")
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.preferredWidth: 72
                    text: modelData.device
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.monospace
                }

                StyledText {
                    Layout.preferredWidth: 72
                    text: modelData.type
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                Rectangle {
                    readonly property bool active: modelData.state.startsWith("connected")
                    implicitWidth: stateText.implicitWidth + 14
                    implicitHeight: stateText.implicitHeight + 6
                    radius: height / 2
                    color: active
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colLayer2

                    StyledText {
                        id: stateText
                        anchors.centerIn: parent
                        text: modelData.state
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: parent.active
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colSubtext
                    }
                }
            }
        }

        StyledText {
            visible: root.ifaces.length === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Loading…")
            color: Appearance.colors.colSubtext
        }
    }

    // ── Wi-Fi ──────────────────────────────────────────────────────────────
    ContentSection {
        icon: Network.wifiEnabled ? "wifi" : "wifi_off"
        title: Translation.tr("Wi-Fi") + (root.wifiDevice ? "  ·  " + root.wifiDevice : "")

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
                mainText: Network.wifiScanning ? Translation.tr("Scanning…") : Translation.tr("Scan")
                enabled: !Network.wifiScanning && Network.wifiEnabled
                onClicked: Network.rescanWifi()
            }
        }

        // ── Connected network banner with full details ──
        Rectangle {
            visible: Network.active !== null && Network.wifi
            Layout.fillWidth: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSecondaryContainer
            implicitHeight: bannerContent.implicitHeight + 20

            ColumnLayout {
                id: bannerContent
                anchors { fill: parent; margins: 10 }
                spacing: 8

                // SSID + signal + Disconnect
                RowLayout {
                    spacing: 8

                    MaterialSymbol {
                        property int s: Network.networkStrength
                        text: s > 80 ? "signal_wifi_4_bar"
                            : s > 60 ? "network_wifi_3_bar"
                            : s > 40 ? "network_wifi_2_bar"
                            : s > 20 ? "network_wifi_1_bar"
                            : "signal_wifi_0_bar"
                        iconSize: 20
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Network.networkName
                            + (Network.networkStrength > 0
                                ? "  ·  " + Network.networkStrength + "%"
                                : "")
                        color: Appearance.colors.colOnSecondaryContainer
                        font.weight: Font.Medium
                    }

                    RippleButton {
                        buttonRadius: Appearance.rounding.full
                        implicitWidth: 100
                        implicitHeight: 30
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

                // Two-column grid of details
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 2
                    columnSpacing: 24

                    ActiveNetRow { dlabel: Translation.tr("IP Address"); dvalue: root.wifiIp;      mono: true }
                    ActiveNetRow { dlabel: Translation.tr("Gateway");    dvalue: root.wifiGateway;  mono: true }
                    ActiveNetRow { dlabel: Translation.tr("DNS");        dvalue: root.wifiDns;      mono: true }
                    ActiveNetRow { dlabel: Translation.tr("MAC");        dvalue: root.wifiMac;      mono: true }
                    ActiveNetRow {
                        dlabel: "BSSID"
                        dvalue: Network.active?.bssid ?? ""
                        mono: true
                    }
                    ActiveNetRow {
                        dlabel: Translation.tr("Frequency")
                        dvalue: {
                            const f = Network.active?.frequency ?? 0
                            if (!f) return "—"
                            return (f > 4900 ? "5 GHz" : "2.4 GHz") + "  ·  " + f + " MHz"
                        }
                    }
                    ActiveNetRow {
                        dlabel: Translation.tr("Security")
                        dvalue: Network.active?.security || Translation.tr("Open")
                    }
                    ActiveNetRow {
                        dlabel: Translation.tr("Signal")
                        dvalue: Network.active ? Network.active.strength + "%" : ""
                    }
                }
            }
        }

        // ── Available networks ──
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
                    : netMouse.containsMouse && !netItem.expanded
                        ? Appearance.colors.colLayer1Hover
                        : Appearance.colors.colLayer1
                property bool expanded: false

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                ColumnLayout {
                    id: netCol
                    anchors { fill: parent; margins: 8 }
                    spacing: 4

                    // Summary row
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
                            visible: (netItem.modelData?.strength ?? 0) > 0
                            text: (netItem.modelData?.strength ?? 0) + "%"
                            color: netItem.modelData.active
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }

                        MaterialSymbol {
                            visible: !!(netItem.modelData?.isSecure)
                            text: "lock"
                            iconSize: 14
                            color: netItem.modelData.active
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colSubtext
                        }

                        MaterialSymbol {
                            visible: Network.wifiConnecting
                                && (Network.wifiConnectTarget?.ssid === netItem.modelData?.ssid)
                            text: "autorenew"
                            iconSize: 16
                            color: Appearance.colors.colSubtext
                        }

                        MaterialSymbol {
                            visible: !Network.wifiConnecting
                                || (Network.wifiConnectTarget?.ssid !== netItem.modelData?.ssid)
                            text: netItem.expanded ? "expand_less" : "expand_more"
                            iconSize: 16
                            color: netItem.modelData.active
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colSubtext
                        }
                    }

                    // Expanded: BSSID / freq / security + connect button
                    ColumnLayout {
                        visible: netItem.expanded && !(netItem.modelData?.askingPassword ?? false)
                        Layout.fillWidth: true
                        spacing: 4

                        GridLayout {
                            columns: 4
                            rowSpacing: 3
                            columnSpacing: 8

                            StyledText {
                                text: "BSSID"
                                color: netItem.modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledText {
                                text: netItem.modelData?.bssid || "—"
                                color: netItem.modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.monospace
                            }
                            StyledText {
                                text: Translation.tr("Frequency")
                                color: netItem.modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledText {
                                readonly property int f: netItem.modelData?.frequency ?? 0
                                text: f ? ((f > 4900 ? "5 GHz  ·  " : "2.4 GHz  ·  ") + f + " MHz") : "—"
                                color: netItem.modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledText {
                                text: Translation.tr("Security")
                                color: netItem.modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledText {
                                text: netItem.modelData?.security || Translation.tr("Open")
                                color: netItem.modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledText {
                                text: Translation.tr("Signal")
                                color: netItem.modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledText {
                                text: (netItem.modelData?.strength ?? 0) + "%"
                                color: netItem.modelData.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }

                        RowLayout {
                            visible: !netItem.modelData.active
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            DialogButton {
                                buttonText: Translation.tr("Connect")
                                onClicked: Network.connectToWifiNetwork(netItem.modelData)
                            }
                        }
                    }

                    // Password prompt
                    ColumnLayout {
                        visible: netItem.modelData?.askingPassword ?? false
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialTextField {
                            id: pwField
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Password for ") + (netItem.modelData?.ssid ?? "")
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
                    id: netMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    visible: !(netItem.modelData?.askingPassword ?? false)
                    onClicked: netItem.expanded = !netItem.expanded
                }
            }
        }

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

    // ── Ethernet ───────────────────────────────────────────────────────────
    ContentSection {
        icon: Network.ethernet ? "lan" : "cable"
        title: Translation.tr("Ethernet") + (root.ethDevice ? "  ·  " + root.ethDevice : "")

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialSymbol {
                text: Network.ethernet ? "check_circle" : "cancel"
                iconSize: 20
                color: Network.ethernet ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            StyledText {
                Layout.fillWidth: true
                text: Network.ethernet
                    ? Translation.tr("Connected")
                    : root.ethDevice
                        ? Translation.tr("Adapter present — not connected")
                        : Translation.tr("No Ethernet adapter detected")
                color: Network.ethernet ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
            }
        }

        ColumnLayout {
            visible: Network.ethernet || root.ethDevice !== ""
            Layout.fillWidth: true
            spacing: 4

            EthDetailRow { elabel: Translation.tr("IP Address");  evalue: root.ethIp;      mono: true }
            EthDetailRow { elabel: Translation.tr("Gateway");     evalue: root.ethGateway; mono: true }
            EthDetailRow { elabel: Translation.tr("DNS");         evalue: root.ethDns;     mono: true }
            EthDetailRow { elabel: Translation.tr("MAC");         evalue: root.ethMac;     mono: true }
            EthDetailRow { elabel: Translation.tr("Interface");   evalue: root.ethDevice;  mono: true }
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
                                let s = modelData.connected
                                    ? Translation.tr("Connected")
                                    : Translation.tr("Paired")
                                if (modelData.batteryAvailable)
                                    s += "  ·  " + Math.round(modelData.battery * 100) + "%"
                                return s
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
                        implicitWidth: 100
                        implicitHeight: 30
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

    // ── Network tools ──────────────────────────────────────────────────────
    ContentSection {
        icon: "settings"
        title: Translation.tr("Network tools")

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "settings"
                mainText: Translation.tr("Network settings app")
                onClicked: Quickshell.execDetached(["bash", "-c", Config.options.apps.network])
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "open_in_browser"
                mainText: Translation.tr("Captive portal login")
                onClicked: Network.openPublicWifiPortal()
            }
        }
    }
}
