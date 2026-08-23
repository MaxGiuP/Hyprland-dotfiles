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
        if (!getEthernetDevices.running)
            getEthernetDevices.running = true;
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
                getNetworks.running = true
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
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser {
            onRead: getNetworks.running = true
        }
        onExited: exitCode => {
            getNetworks.running = true;
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
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        stdout: SplitParser {
            onRead: {
                wifiScanning = false;
                getNetworks.running = true;
            }
        }
    }

    // Status update
    function update() {
        updateConnectionType.startCheck();
        root.refreshEthernetDevices();
        wifiStatusProcess.running = true
        updateNetworkName.running = true;
        updateNetworkStrength.running = true;
    }

    Process {
        id: subscriber
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: root.update()
        }
    }

    Process {
        id: updateConnectionType
        property string buffer
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE d status && nmcli -t -f CONNECTIVITY g"]
        running: true
        environment: ({ LANG: "C", LC_ALL: "C" })
        function startCheck() {
            buffer = "";
            updateConnectionType.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                updateConnectionType.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            const lines = updateConnectionType.buffer.trim().split('\n');
            const connectivity = lines.pop() // none, limited, full
            let hasEthernet = false;
            let hasWifi = false;
            let wifiStatus = "disconnected";
            lines.forEach(line => {
                const separator = line.indexOf(":");
                const type = separator >= 0 ? line.slice(0, separator) : line;
                const state = separator >= 0 ? line.slice(separator + 1) : "";
                if (type === "ethernet" && state.startsWith("connected"))
                    hasEthernet = true;
                else if (type === "wifi") {
                    if (state.startsWith("disconnected")) {
                        if (!hasWifi && wifiStatus !== "connecting")
                            wifiStatus = "disconnected"
                    }
                    else if (state.startsWith("connected")) {
                        hasWifi = true;
                        wifiStatus = connectivity === "full" ? "connected" : connectivity
                    }
                    else if (state.startsWith("connecting")) {
                        if (!hasWifi)
                            wifiStatus = "connecting"
                    }
                    else if (state.startsWith("unavailable")) {
                        if (!hasWifi && wifiStatus !== "connecting")
                            wifiStatus = "disabled"
                    }
                }
            });
            root.wifiStatus = wifiStatus;
            root.ethernet = hasEthernet;
            root.wifi = hasWifi;
        }
    }

    Process {
        id: updateNetworkName
        command: ["sh", "-c", "nmcli -t -f TYPE,NAME connection show --active | awk -F: '$1 == \"802-11-wireless\" { print substr($0, index($0, \":\") + 1); exit }'"]
        running: true
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                root.networkName = text.trim();
            }
        }
    }

    Process {
        id: updateNetworkStrength
        running: true
        command: ["sh", "-c", "nmcli -f IN-USE,SIGNAL,SSID device wifi | awk '/^\*/{if (NR!=1) {print $2}}'"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                root.networkStrength = parseInt(text.trim()) || 0;
            }
        }
    }

    Process {
        id: wifiStatusProcess
        command: ["nmcli", "radio", "wifi"]
        running: true
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiEnabled = text.trim() === "enabled";
            }
        }
    }

    Process {
        id: getNetworks
        running: true
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY", "d", "w"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
                const rep = new RegExp("\\\\:", "g");
                const rep2 = new RegExp(PLACEHOLDER, "g");

                const allNetworks = text.trim().split("\n").map(n => {
                    const net = n.replace(rep, PLACEHOLDER).split(":");
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]),
                        frequency: parseInt(net[2]),
                        ssid: net[3],
                        bssid: net[4]?.replace(rep2, ":") ?? "",
                        security: net[5] || ""
                    };
                }).filter(n => n.ssid && n.ssid.length > 0);

                // Group networks by SSID and prioritize connected ones
                const networkMap = new Map();
                for (const network of allNetworks) {
                    const existing = networkMap.get(network.ssid);
                    if (!existing) {
                        networkMap.set(network.ssid, network);
                    } else {
                        // Prioritize active/connected networks
                        if (network.active && !existing.active) {
                            networkMap.set(network.ssid, network);
                        } else if (!network.active && !existing.active) {
                            // If both are inactive, keep the one with better signal
                            if (network.strength > existing.strength) {
                                networkMap.set(network.ssid, network);
                            }
                        }
                        // If existing is active and new is not, keep existing
                    }
                }

                const wifiNetworks = Array.from(networkMap.values());

                const rNetworks = root.wifiNetworks;

                const destroyed = rNetworks.filter(rn => !wifiNetworks.find(n => n.frequency === rn.frequency && n.ssid === rn.ssid && n.bssid === rn.bssid));
                for (const network of destroyed)
                    rNetworks.splice(rNetworks.indexOf(network), 1).forEach(n => n.destroy());

                for (const network of wifiNetworks) {
                    const match = rNetworks.find(n => n.frequency === network.frequency && n.ssid === network.ssid && n.bssid === network.bssid);
                    if (match) {
                        match.lastIpcObject = network;
                    } else {
                        rNetworks.push(apComp.createObject(root, {
                            lastIpcObject: network
                        }));
                    }
                }
            }
        }
    }

    Process {
        id: getEthernetDevices
        running: true
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
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

                root.ethernetDevices = text.trim().split("\n")
                    .filter(line => line.length > 0)
                    .map(line => splitEscapedFields(line))
                    .filter(fields => fields.length >= 3 && fields[1] === "ethernet")
                    .map(fields => {
                        const state = fields[2] ?? "unknown";
                        return {
                            device: fields[0] ?? "",
                            state: state,
                            connection: (fields[3] ?? "").replace(/^--$/, ""),
                            connected: state === "connected",
                            connecting: state === "connecting",
                            available: state !== "unmanaged" && state !== "unavailable"
                        };
                    });
            }
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
            root.refreshEthernetDevices();
            root.update();
        }
    }

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
