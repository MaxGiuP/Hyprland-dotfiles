pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.network

/**
 * Network service with nmcli.
 */
Singleton {
    id: root

    property bool wifi: true
    property bool ethernet: false

    property bool wifiEnabled: false
    property bool wifiScanning: false
    property bool wifiConnecting: connectProc.running
    property list<var> ethernetDevices: []
    property string ethernetActionDevice: ""
    readonly property bool ethernetActionRunning: ethernetActionProc.running
    readonly property list<var> friendlyEthernetDevices: [...ethernetDevices].sort((a, b) => {
        if (a.connected && !b.connected)
            return -1;
        if (!a.connected && b.connected)
            return 1;
        return a.device.localeCompare(b.device);
    })
    property WifiAccessPoint wifiConnectTarget
    property WifiAccessPoint pendingWifiSwitchTarget
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        if (a.active && !b.active)
            return -1;
        if (!a.active && b.active)
            return 1;
        return b.strength - a.strength;
    })
    property string wifiStatus: "disconnected"
    property bool statusRefreshQueued: false
    property int networkMonitorRetryAttempt: 0

    property string networkName: ""
    property int networkStrength
    readonly property string wifiMaterialSymbol: !root.wifiEnabled
        ? "signal_wifi_off"
        : root.wifi
            ? root.wifiStatus !== "connected"
                ? "signal_wifi_bad"
                : (
                    Network.networkStrength > 83 ? "signal_wifi_4_bar" :
                    Network.networkStrength > 67 ? "network_wifi" :
                    Network.networkStrength > 50 ? "network_wifi_3_bar" :
                    Network.networkStrength > 33 ? "network_wifi_2_bar" :
                    Network.networkStrength > 17 ? "network_wifi_1_bar" :
                    "signal_wifi_0_bar"
                )
            : (root.wifiStatus === "connecting")
                ? "signal_wifi_statusbar_not_connected"
                : (root.wifiStatus === "disconnected")
                    ? "wifi_find"
                    : "signal_wifi_bad"
    readonly property string materialSymbol: root.ethernet ? "lan" : root.wifiMaterialSymbol

    // Control
    function enableWifi(enabled = true): void {
        const cmd = enabled ? "on" : "off";
        enableWifiProc.exec(["nmcli", "radio", "wifi", cmd]);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function refreshEthernetDevices(): void {
        root.update();
    }

    function toggleEthernetDevice(device): void {
        if (!device || !device.available || ethernetActionProc.running)
            return;

        root.ethernetActionDevice = device.device;
        ethernetActionProc.exec([
            "nmcli", "device", device.connected ? "disconnect" : "connect", device.device
        ]);
    }

    function rescanWifi(): void {
        if (rescanProcess.running)
            return;
        wifiScanning = true;
        rescanProcess.running = true;
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        if (!accessPoint)
            return;

        if (accessPoint.active) {
            root.wifiConnectTarget = null;
            root.pendingWifiSwitchTarget = null;
            return;
        }

        accessPoint.askingPassword = false;
        if (root.active && root.active.ssid !== accessPoint.ssid) {
            root.pendingWifiSwitchTarget = accessPoint;
            disconnectWifiNetwork();
            return;
        }

        root.pendingWifiSwitchTarget = null;
        root.wifiConnectTarget = accessPoint;
        // We use this instead of `nmcli connection up SSID` because this also creates a connection profile
        connectProc.exec(["nmcli", "dev", "wifi", "connect", accessPoint.ssid])

    }

    function disconnectWifiNetwork(): void {
        if (active)
            disconnectProc.exec(["nmcli", "connection", "down", active.ssid]);
    }

    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]) // From some StackExchange thread, seems to work
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        network.askingPassword = false;
        changePasswordProc.exec({
            "environment": {
                "PASSWORD": password,
                "SSID": network.ssid
            },
            "command": ["bash", "-c", 'nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"']
        })
    }

    Process {
        id: enableWifiProc
        onExited: root.update()
    }

    Process {
        id: connectProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: SplitParser {
            onRead: line => {
                // print(line)
                root.update()
            }
        }
        stderr: SplitParser {
            onRead: line => {
                // print("err:", line)
                if (line.includes("Secrets were required")) {
                    root.wifiConnectTarget.askingPassword = true
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.wifiConnectTarget)
                root.wifiConnectTarget.askingPassword = (exitCode !== 0)
            root.wifiConnectTarget = null
            root.pendingWifiSwitchTarget = null
            root.update()
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser {
            onRead: root.update()
        }
        onExited: exitCode => {
            root.update();
            if (exitCode !== 0)
                return;
            if (!root.pendingWifiSwitchTarget)
                return;

            const target = root.pendingWifiSwitchTarget;
            root.pendingWifiSwitchTarget = null;
            root.connectToWifiNetwork(target);
        }
    }

    Process {
        id: changePasswordProc
        onExited: { // Re-attempt connection after changing password
            connectProc.running = false
            connectProc.running = true
        }
    }

    Process {
        id: rescanProcess
        command: ["nmcli", "device", "wifi", "rescan"]
        onExited: {
            wifiScanning = false;
            root.update();
        }
    }

    // Status update
    function update() {
        root.statusRefreshQueued = true;
        statusRefreshDebounce.restart();
    }

    function scheduleNetworkMonitorRestart() {
        root.networkMonitorRetryAttempt += 1
        networkMonitorRestart.interval = Math.min(
            60000,
            1000 * Math.pow(2, Math.min(root.networkMonitorRetryAttempt - 1, 6))
        )
        networkMonitorRestart.restart()
    }

    function splitEscapedFields(line) {
        const fields = [];
        let field = "";
        let escaped = false;
        for (let i = 0; i < line.length; i++) {
            const character = line[i];
            if (escaped) {
                field += character;
                escaped = false;
            } else if (character === "\\") {
                escaped = true;
            } else if (character === ":") {
                fields.push(field);
                field = "";
            } else {
                field += character;
            }
        }
        fields.push(field);
        return fields;
    }

    function snapshotSection(output, marker, nextMarker) {
        const token = marker + "\n";
        let start = output.indexOf(token);
        if (start < 0)
            return "";
        start += token.length;
        const end = nextMarker ? output.indexOf(nextMarker + "\n", start) : output.length;
        return output.slice(start, end < 0 ? output.length : end).trim();
    }

    function applyStatusSnapshot(output) {
        const general = root.splitEscapedFields(root.snapshotSection(
            output, "__II_GENERAL__", "__II_DEVICES__"
        ).split("\n")[0] || "");
        const wifiEnabled = general[0] === "enabled";
        const connectivity = general[1] || "none";

        const deviceRows = root.snapshotSection(
            output, "__II_DEVICES__", "__II_WIFI__"
        ).split("\n").filter(line => line.length > 0).map(line => root.splitEscapedFields(line));
        let hasEthernet = false;
        let hasWifi = false;
        let wifiConnecting = false;
        const ethernetDevices = [];
        for (const fields of deviceRows) {
            if (fields.length < 3)
                continue;
            const device = fields[0] || "";
            const type = fields[1] || "";
            const state = fields[2] || "unknown";
            const connection = (fields[3] || "").replace(/^--$/, "");
            if (type === "ethernet") {
                const connected = state.startsWith("connected");
                hasEthernet = hasEthernet || connected;
                ethernetDevices.push({
                    device,
                    state,
                    connection,
                    connected,
                    connecting: state.startsWith("connecting"),
                    available: state !== "unmanaged" && state !== "unavailable"
                });
            } else if (type === "wifi") {
                hasWifi = hasWifi || state.startsWith("connected");
                wifiConnecting = wifiConnecting || state.startsWith("connecting");
            }
        }

        const wifiRows = root.snapshotSection(output, "__II_WIFI__", "")
            .split("\n").filter(line => line.length > 0);
        const allNetworks = wifiRows.map(line => {
            const fields = root.splitEscapedFields(line);
            return {
                active: fields[0] === "yes",
                strength: parseInt(fields[1]) || 0,
                frequency: parseInt(fields[2]) || 0,
                ssid: fields[3] || "",
                bssid: fields[4] || "",
                security: fields[5] || ""
            };
        }).filter(network => network.ssid.length > 0);

        const networkMap = new Map();
        for (const network of allNetworks) {
            const existing = networkMap.get(network.ssid);
            if (!existing || (network.active && !existing.active)
                    || (!network.active && !existing.active && network.strength > existing.strength))
                networkMap.set(network.ssid, network);
        }
        const nextNetworks = Array.from(networkMap.values());
        const currentNetworks = root.wifiNetworks;
        const destroyed = currentNetworks.filter(current => !nextNetworks.find(network =>
            network.frequency === current.frequency && network.ssid === current.ssid && network.bssid === current.bssid
        ));
        for (const network of destroyed)
            currentNetworks.splice(currentNetworks.indexOf(network), 1).forEach(item => item.destroy());
        for (const network of nextNetworks) {
            const match = currentNetworks.find(current =>
                network.frequency === current.frequency && network.ssid === current.ssid && network.bssid === current.bssid
            );
            if (match)
                match.lastIpcObject = network;
            else
                currentNetworks.push(apComp.createObject(root, { lastIpcObject: network }));
        }

        const activeNetwork = nextNetworks.find(network => network.active) ?? null;
        root.wifiEnabled = wifiEnabled;
        root.ethernet = hasEthernet;
        root.wifi = hasWifi;
        root.wifiStatus = !wifiEnabled ? "disabled"
            : wifiConnecting && !hasWifi ? "connecting"
            : hasWifi ? (connectivity === "full" ? "connected" : connectivity)
            : "disconnected";
        root.ethernetDevices = ethernetDevices;
        root.networkName = activeNetwork?.ssid ?? "";
        root.networkStrength = activeNetwork?.strength ?? 0;
    }

    Process {
        id: subscriber
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: root.update()
        }
        onRunningChanged: {
            if (running)
                networkMonitorStable.restart()
            else
                networkMonitorStable.stop()
        }
        onExited: root.scheduleNetworkMonitorRestart()
    }

    Timer {
        id: networkMonitorRestart
        interval: 1000
        repeat: false
        onTriggered: {
            if (!subscriber.running) {
                subscriber.running = true;
                root.update();
            }
        }
    }

    Timer {
        id: networkMonitorStable
        interval: 30000
        repeat: false
        onTriggered: root.networkMonitorRetryAttempt = 0
    }

    // NetworkManager can emit several monitor lines for one state transition.
    // Coalesce them, then run the three independent nmcli reads serially in one
    // bounded process instead of launching a parallel process fan-out.
    Timer {
        id: statusRefreshDebounce
        interval: 300
        repeat: false
        onTriggered: {
            if (statusSnapshotProcess.running || rescanProcess.running)
                return;
            root.statusRefreshQueued = false;
            statusSnapshotProcess.running = true;
        }
    }

    Timer {
        // Reconcile occasionally in case NetworkManager or its monitor was
        // unavailable during a transition. Normal updates remain event-driven.
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.update()
    }

    Process {
        id: statusSnapshotProcess
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["/bin/sh", "-c",
            "set -e; printf '__II_GENERAL__\\n'; "
            + "nmcli -t -f WIFI,CONNECTIVITY general; "
            + "printf '__II_DEVICES__\\n'; "
            + "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status; "
            + "printf '__II_WIFI__\\n'; "
            + "nmcli -g ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY device wifi list --rescan no"
        ]
        stdout: StdioCollector {
            id: statusSnapshotCollector
        }
        onExited: (exitCode, exitStatus) => {
            const output = statusSnapshotCollector.text;
            const generalMarker = output.indexOf("__II_GENERAL__\n");
            const devicesMarker = output.indexOf("__II_DEVICES__\n");
            const wifiMarker = output.indexOf("__II_WIFI__\n");
            if (exitCode === 0 && generalMarker === 0
                    && devicesMarker > generalMarker && wifiMarker > devicesMarker)
                root.applyStatusSnapshot(output);
            if (root.statusRefreshQueued)
                statusRefreshDebounce.restart();
        }
    }

    Process {
        id: ethernetActionProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        onExited: {
            root.ethernetActionDevice = "";
            root.update();
        }
    }

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
