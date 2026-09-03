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
    property var settingsHost: null

    readonly property var trackedOutputDevices: Audio.outputDevices.filter(d => d.name !== "qs_mono_out")
    readonly property var realOutputDevices: Audio.selectableOutputDevices.filter(d => d.name !== "qs_mono_out")
    readonly property var adapters: Bluetooth.adapters?.values ?? []
    property string selectedAdapterId: Bluetooth.defaultAdapter?.adapterId ?? ""
    readonly property var selectedAdapter: root.adapters.find(adapter => adapter.adapterId === root.selectedAdapterId)
        ?? Bluetooth.defaultAdapter
        ?? null
    readonly property var selectedDevices: {
        const devices = root.selectedAdapter?.devices?.values ?? []
        return devices.slice().sort((left, right) => {
            if (left.connected !== right.connected) return left.connected ? -1 : 1
            if (left.paired !== right.paired) return left.paired ? -1 : 1
            return (left.name || left.address).localeCompare(right.name || right.address)
        })
    }
    readonly property bool isDiscovering: root.selectedAdapter?.discovering ?? false
    readonly property bool selectedConnected: root.selectedDevices.some(device => device.connected)

    function scrollToSection(sectionId) {
        const map = {
            "overview": btOverviewSection,
            "adapter": btAdapterSection,
            "devices": btDevicesSection,
            "audio": btIntegratedSection
        }
        const target = map[sectionId]
        if (target) root.contentY = Math.max(0, target.y - 10)
    }

    function navigate(page, subTab = -1, sectionId = "") {
        if (root.settingsHost && typeof root.settingsHost.applyNavigation === "function")
            root.settingsHost.applyNavigation(typeof page === "string" ? SettingsCatalog.indexOf(page) : page, subTab, sectionId)
    }

    PwObjectTracker {
        objects: root.trackedOutputDevices
    }

    Timer {
        id: scanTimer
        interval: 30000
        onTriggered: {
            if (root.selectedAdapter?.discovering)
                root.selectedAdapter.discovering = false
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
                buttonIcon: root.selectedConnected ? "bluetooth_connected" : root.selectedAdapter?.enabled ? "bluetooth" : "bluetooth_disabled"
                text: root.selectedConnected
                    ? (root.selectedDevices.find(device => device.connected)?.name ?? Translation.tr("Bluetooth connected"))
                    : root.selectedAdapter?.enabled
                        ? Translation.tr("Bluetooth on")
                        : Translation.tr("Bluetooth off")
                checked: root.selectedAdapter?.enabled ?? false
                enabled: root.selectedAdapter !== null
                onClicked: if (root.selectedAdapter) root.selectedAdapter.enabled = checked
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
        id: btAdapterSection
        icon: "settings_bluetooth"
        title: Translation.tr("Adapter")
        description: root.selectedAdapter
            ? Translation.tr("%1 · %2 · %3")
                .arg(root.selectedAdapter.name)
                .arg(root.selectedAdapter.adapterId)
                .arg(BluetoothAdapterState.toString(root.selectedAdapter.state))
            : Translation.tr("No BlueZ adapter detected")

        StyledComboBox {
            visible: root.adapters.length > 1
            Layout.fillWidth: true
            buttonIcon: "settings_bluetooth"
            textRole: "displayName"
            model: root.adapters.map(adapter => ({
                displayName: `${adapter.name} · ${adapter.adapterId}`,
                adapterId: adapter.adapterId
            }))
            currentIndex: Math.max(0, root.adapters.findIndex(adapter => adapter.adapterId === root.selectedAdapterId))
            onActivated: index => root.selectedAdapterId = root.adapters[index].adapterId
        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "visibility"
                text: checked ? Translation.tr("Visible to nearby devices") : Translation.tr("Not discoverable")
                enabled: root.selectedAdapter?.enabled ?? false
                checked: root.selectedAdapter?.discoverable ?? false
                onClicked: if (root.selectedAdapter) root.selectedAdapter.discoverable = checked
            }

            ConfigSwitch {
                buttonIcon: "add_link"
                text: checked ? Translation.tr("Ready to pair") : Translation.tr("Pairing disabled")
                enabled: root.selectedAdapter?.enabled ?? false
                checked: root.selectedAdapter?.pairable ?? false
                onClicked: if (root.selectedAdapter) root.selectedAdapter.pairable = checked
            }
        }

        ConfigRow {
            uniform: true

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Visibility timeout (s)")
                enabled: root.selectedAdapter !== null
                from: 0
                to: 3600
                stepSize: 30
                value: root.selectedAdapter?.discoverableTimeout ?? 0
                onValueChanged: if (root.selectedAdapter && root.selectedAdapter.discoverableTimeout !== value) root.selectedAdapter.discoverableTimeout = value
            }

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Pairing timeout (s)")
                enabled: root.selectedAdapter !== null
                from: 0
                to: 3600
                stepSize: 30
                value: root.selectedAdapter?.pairableTimeout ?? 0
                onValueChanged: if (root.selectedAdapter && root.selectedAdapter.pairableTimeout !== value) root.selectedAdapter.pairableTimeout = value
            }
        }

        StyledText {
            Layout.fillWidth: true
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("A timeout of 0 leaves the adapter visible or pairable until you turn it off. These controls talk directly to BlueZ.")
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
                enabled: root.selectedAdapter?.enabled ?? false
                toggled: root.isDiscovering
                onClicked: {
                    if (!root.selectedAdapter) return
                    if (root.isDiscovering) {
                        root.selectedAdapter.discovering = false
                        scanTimer.stop()
                    } else {
                        root.selectedAdapter.discovering = true
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
            model: root.selectedDevices

            delegate: Rectangle {
                id: deviceCard
                required property var modelData
                property bool expanded: false
                Layout.fillWidth: true
                implicitHeight: deviceCardContent.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: modelData.connected
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOutlineVariant

                ColumnLayout {
                    id: deviceCardContent
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        id: deviceRow
                        Layout.fillWidth: true
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

                            RippleButton {
                                implicitWidth: 38
                                implicitHeight: 38
                                buttonRadius: Appearance.rounding.full
                                onClicked: deviceCard.expanded = !deviceCard.expanded

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "expand_more"
                                    iconSize: 20
                                    rotation: deviceCard.expanded ? 180 : 0
                                    color: Appearance.colors.colOnLayer1
                                    Behavior on rotation {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: deviceCard.expanded
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Appearance.colors.colOutlineVariant
                        opacity: 0.6
                    }

                    ColumnLayout {
                        visible: deviceCard.expanded
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                StyledText {
                                    text: Translation.tr("Device address")
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.address || Translation.tr("Unavailable")
                                    color: Appearance.colors.colOnLayer1
                                    font.family: Appearance.font.family.monospace
                                    elide: Text.ElideRight
                                }
                            }

                            StyledText {
                                text: modelData.bonded ? Translation.tr("Bonded") : modelData.paired ? Translation.tr("Paired") : Translation.tr("Not paired")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }

                        MaterialTextField {
                            id: deviceAliasField
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Device name")
                            text: modelData.name || ""
                            onEditingFinished: {
                                const alias = text.trim()
                                if (alias.length > 0 && alias !== modelData.name)
                                    modelData.name = alias
                            }
                        }

                        ConfigRow {
                            uniform: true

                            ConfigSwitch {
                                buttonIcon: "verified_user"
                                text: Translation.tr("Trusted")
                                enabled: modelData.paired
                                checked: modelData.trusted
                                onClicked: if (modelData.trusted !== checked) modelData.trusted = checked
                            }

                            ConfigSwitch {
                                buttonIcon: "block"
                                text: Translation.tr("Blocked")
                                checked: modelData.blocked
                                onClicked: if (modelData.blocked !== checked) modelData.blocked = checked
                            }

                            ConfigSwitch {
                                buttonIcon: "power_settings_new"
                                text: Translation.tr("Wake allowed")
                                enabled: modelData.paired
                                checked: modelData.wakeAllowed
                                onClicked: if (modelData.wakeAllowed !== checked) modelData.wakeAllowed = checked
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Trust permits automatic services from this paired device. Blocking prevents future connections until it is turned off.")
                        }
                    }
                }
            }
        }

        StyledText {
            visible: root.selectedDevices.length === 0 && !root.isDiscovering
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.selectedAdapter?.enabled
                ? Translation.tr("No Bluetooth devices found. Tap \"Scan for devices\" to search.")
                : Translation.tr("Enable Bluetooth to see devices.")
            color: Appearance.colors.colSubtext
        }

        StyledText {
            visible: root.selectedDevices.length === 0 && root.isDiscovering
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Scanning for nearby devices…")
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        id: btIntegratedSection
        icon: "hub"
        title: Translation.tr("Related settings")
        description: Translation.tr("Stay inside the custom control centre")

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "volume_up"
                mainText: Translation.tr("Sound & audio routing")
                onClicked: root.navigate("audio", 0, "output")
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "mouse"
                mainText: Translation.tr("Input devices")
                onClicked: root.navigate("peripherals", 0, "devices")
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "display_settings"
                mainText: Translation.tr("Displays")
                onClicked: root.navigate("display", 0, "display")
            }
        }
    }
}
