pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property var adapters: Bluetooth.adapters.values
    // Keep an explicit choice when it is powered off or temporarily unplugged.
    property string selectedAdapterId: ""
    readonly property var activeAdapter: adapters.find(adapter => adapter.adapterId === selectedAdapterId)
        ?? adapters.find(adapter => adapter.devices.values.some(device => device.connected))
        ?? adapters.find(adapter => adapter.enabled)
        ?? adapters[0]
        ?? null
    readonly property var devices: activeAdapter?.devices?.values ?? []
    readonly property bool available: adapters.length > 0
    readonly property bool enabled: activeAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: connectedDevices[0] ?? null
    readonly property int activeDeviceCount: connectedDevices.length
    readonly property bool connected: activeDeviceCount > 0

    function selectAdapter(adapterId: string): bool {
        if (!root.adapters.some(adapter => adapter.adapterId === adapterId))
            return false;
        root.selectedAdapterId = adapterId;
        return true;
    }

    function setEnabled(value: bool): void {
        const adapter = root.activeAdapter;
        if (!adapter)
            return;
        root.selectAdapter(adapter.adapterId);
        if (!value && adapter.discovering)
            adapter.discovering = false;
        adapter.enabled = value;
    }

    function toggleEnabled(): void {
        root.setEnabled(!root.enabled);
    }

    function setDiscovering(value: bool): void {
        const adapter = root.activeAdapter;
        if (!adapter || (value && !adapter.enabled) || (!value && !adapter.discovering))
            return;
        if (value)
            root.selectAdapter(adapter.adapterId);
        adapter.discovering = value;
    }

    function toggleDiscovering(): void {
        root.setDiscovering(!(root.activeAdapter?.discovering ?? false));
    }

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }
    property list<var> connectedDevices: root.devices.filter(d => d.connected).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: root.devices.filter(d => d.paired && !d.connected).sort(sortFunction)
    property list<var> unpairedDevices: root.devices.filter(d => !d.paired && !d.connected).sort(sortFunction)
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]

    IpcHandler {
        target: "bluetooth"

        function activeAdapterId(): string {
            return root.activeAdapter?.adapterId ?? "";
        }

        function selectAdapter(adapterId: string): bool {
            return root.selectAdapter(adapterId);
        }
    }
}
