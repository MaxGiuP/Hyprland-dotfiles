import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

    forceWidth: true
    baseWidth: 760

    property var settingsHost: null
    property int currentTab: 0
    property string hostName: ""
    property var capabilities: ({})
    property var pendingCapabilities: ({})
    property var systemUnits: ({})
    property var userUnits: ({})
    property bool capabilitiesReady: false
    property bool systemUnitsReady: false
    property bool userUnitsReady: false
    property bool kdeDevicesReady: false
    property int connectedKdeDeviceCount: 0
    property string userServiceActionStatus: ""

    readonly property var tabs: [
        { name: Translation.tr("Overview"), icon: "share" },
        { name: Translation.tr("Remote access"), icon: "lan" },
        { name: Translation.tr("Nearby & services"), icon: "devices_other" }
    ]

    readonly property var systemUnitCandidates: [
        "sshd.service",
        "ssh.service",
        "avahi-daemon.service",
        "smb.service",
        "smbd.service",
        "samba.service",
        "cups.service",
        "cupsd.service"
    ]
    readonly property var kdeConnectUserUnitCandidates: [
        "app-org.kde.kdeconnect.daemon@autostart.service",
        "kdeconnect.service",
        "kdeconnectd.service"
    ]

    readonly property string deviceLabel: root.hostName.length > 0
        ? root.hostName : Translation.tr("This device")
    readonly property string deviceIdentity: {
        const user = String(SystemInfo.username || "")
        if (user.length > 0 && root.hostName.length > 0)
            return `${user}@${root.hostName}`
        return user.length > 0 ? user : root.deviceLabel
    }

    readonly property var sshService: root.systemService(
        "ssh", Translation.tr("Secure Shell"), "terminal",
        ["sshd"], ["sshd.service", "ssh.service"],
        Translation.tr("Encrypted command-line access to this device."))
    readonly property var sambaService: root.systemService(
        "samba", Translation.tr("SMB file sharing"), "folder_shared",
        ["smbd", "samba"], ["smb.service", "smbd.service", "samba.service"],
        Translation.tr("Windows-compatible folders and network shares."))
    readonly property var avahiService: root.systemService(
        "avahi", Translation.tr("Nearby discovery"), "radar",
        ["avahi-daemon"], ["avahi-daemon.service"],
        Translation.tr("Advertises and discovers devices on the local network."))
    readonly property var cupsService: root.systemService(
        "cups", Translation.tr("Printer sharing"), "print",
        ["cupsd"], ["cups.service", "cupsd.service"],
        Translation.tr("Provides local and network printing through CUPS."))
    readonly property string kdeConnectUserUnit: root.firstLoadedUnit(
        root.kdeConnectUserUnitCandidates, root.userUnits)
    readonly property var kdeConnectService: root.kdeService()
    readonly property int availableServiceCount: [
        root.sshService,
        root.sambaService,
        root.avahiService,
        root.cupsService,
        root.kdeConnectService
    ].filter(entry => entry.installed).length
    readonly property int activeServiceCount: [
        root.sshService,
        root.sambaService,
        root.avahiService,
        root.cupsService,
        root.kdeConnectService
    ].filter(entry => entry.active).length
    readonly property bool refreshing: capabilityProbe.running
        || systemUnitProbe.running
        || userUnitProbe.running
        || kdeDeviceProbe.running
    readonly property bool kdeUserUnitActive: {
        const state = root.userUnits[root.kdeConnectUserUnit]
        return state?.activeState === "active"
    }

    function applySubTab(subTab, sectionId = "") {
        root.currentTab = Math.max(0, Math.min(Number(subTab), root.tabs.length - 1))
        root.contentY = 0
    }

    function hasCapability(binaryName) {
        return String(root.capabilities[binaryName] || "").length > 0
    }

    function firstLoadedUnit(candidates, states) {
        for (const unit of candidates) {
            const state = states[unit]
            if (state && state.loadState === "loaded")
                return unit
        }
        return ""
    }

    function anyCapability(binaryNames) {
        for (const binaryName of binaryNames) {
            if (root.hasCapability(binaryName))
                return true
        }
        return false
    }

    function statusText(installed, state, checksReady) {
        if (!checksReady)
            return Translation.tr("Checking…")
        if (!installed)
            return Translation.tr("Not installed")
        if (!state)
            return Translation.tr("Installed")
        switch (state.activeState) {
        case "active":
            return state.subState === "running"
                ? Translation.tr("Running") : Translation.tr("Active")
        case "activating":
            return Translation.tr("Starting")
        case "deactivating":
            return Translation.tr("Stopping")
        case "failed":
            return Translation.tr("Failed")
        default:
            return Translation.tr("Stopped")
        }
    }

    function systemService(id, title, icon, binaryNames, unitCandidates, description) {
        const unit = root.firstLoadedUnit(unitCandidates, root.systemUnits)
        const state = unit.length > 0 ? root.systemUnits[unit] : null
        const checksReady = root.capabilitiesReady && root.systemUnitsReady
        const installed = root.anyCapability(binaryNames) || state !== null
        let detail = description
        if (!checksReady)
            detail += " " + Translation.tr("Checking service availability…")
        else if (unit.length > 0)
            detail += ` ${Translation.tr("System service")}: ${unit}`
        else
            detail += " " + Translation.tr("No system service unit was found.")
        return {
            id: id,
            title: title,
            icon: icon,
            installed: installed,
            active: state !== null && state.activeState === "active",
            status: root.statusText(installed, state, checksReady),
            detail: detail,
            unit: unit,
            scope: "system"
        }
    }

    function kdeService() {
        const unit = root.kdeConnectUserUnit
        const state = unit.length > 0 ? root.userUnits[unit] : null
        const checksReady = root.capabilitiesReady && root.userUnitsReady
            && root.kdeDevicesReady
        const installed = root.hasCapability("kdeconnect-cli")
            || root.hasCapability("kdeconnectd") || state !== null
        const active = (state !== null && state.activeState === "active")
            || root.connectedKdeDeviceCount > 0
        let detail = Translation.tr("Links notifications, files and controls with nearby devices.")
        if (!checksReady) {
            detail += " " + Translation.tr("Checking service availability…")
        } else if (root.connectedKdeDeviceCount > 0) {
            detail += " " + Translation.tr("%1 connected device(s).").arg(
                root.connectedKdeDeviceCount)
        } else if (unit.length > 0) {
            detail += ` ${Translation.tr("User service")}: ${unit}`
        } else {
            detail += " " + Translation.tr("No controllable user service unit was found.")
        }
        return {
            id: "kdeconnect",
            title: "KDE Connect",
            icon: "devices",
            installed: installed,
            active: active,
            status: active && (!state || state.activeState !== "active")
                ? Translation.tr("Connected")
                : root.statusText(installed, state, checksReady),
            detail: detail,
            unit: unit,
            scope: "user"
        }
    }

    function parseUnitStates(text) {
        const result = ({})
        const blocks = String(text || "").trim().split(/\n\s*\n/)
        for (const block of blocks) {
            const values = ({})
            for (const line of block.split(/\r?\n/)) {
                const separator = line.indexOf("=")
                if (separator <= 0)
                    continue
                values[line.slice(0, separator)] = line.slice(separator + 1).trim()
            }
            if (values.Id) {
                result[values.Id] = {
                    loadState: values.LoadState || "not-found",
                    activeState: values.ActiveState || "inactive",
                    subState: values.SubState || "dead"
                }
            }
        }
        return result
    }

    function refresh() {
        if (root.refreshing || userServiceAction.running)
            return
        root.capabilitiesReady = false
        root.systemUnitsReady = false
        root.userUnitsReady = false
        root.kdeDevicesReady = false
        root.connectedKdeDeviceCount = 0
        capabilityProbe.running = true
        systemUnitProbe.running = true
        userUnitProbe.running = true
    }

    function refreshKdeDevices() {
        if (!root.hasCapability("kdeconnect-cli")) {
            root.connectedKdeDeviceCount = 0
            root.kdeDevicesReady = true
            return
        }
        if (!kdeDeviceProbe.running)
            kdeDeviceProbe.running = true
    }

    function controlKdeUserService(action) {
        const allowedActions = ["start", "stop", "restart"]
        const unit = root.kdeConnectUserUnit
        if (allowedActions.indexOf(action) < 0
                || root.kdeConnectUserUnitCandidates.indexOf(unit) < 0
                || userServiceAction.running)
            return
        userServiceAction.action = action
        userServiceAction.unit = unit
        root.userServiceActionStatus = Translation.tr("Applying user-service action…")
        userServiceAction.running = true
    }

    Component.onCompleted: {
        hostNameView.reload()
        root.refresh()
    }

    FileView {
        id: hostNameView
        path: "/etc/hostname"
        blockWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.hostName = text().trim()
        onLoadFailed: root.hostName = ""
    }

    Process {
        id: capabilityProbe
        command: [
            "which",
            "sshd",
            "avahi-daemon",
            "smbd",
            "samba",
            "cupsd",
            "kdeconnect-cli",
            "kdeconnectd"
        ]

        onRunningChanged: {
            if (running)
                root.pendingCapabilities = ({})
        }

        stdout: SplitParser {
            onRead: line => {
                const path = line.trim()
                const name = path.slice(path.lastIndexOf("/") + 1)
                if (name.length === 0)
                    return
                const next = Object.assign({}, root.pendingCapabilities)
                next[name] = path
                root.pendingCapabilities = next
            }
        }

        onExited: {
            root.capabilities = root.pendingCapabilities
            root.capabilitiesReady = true
            root.refreshKdeDevices()
        }
    }

    Process {
        id: systemUnitProbe
        command: [
            "systemctl",
            "--no-pager",
            "show",
            "--property=Id",
            "--property=LoadState",
            "--property=ActiveState",
            "--property=SubState"
        ].concat(root.systemUnitCandidates)

        stdout: StdioCollector {
            id: systemUnitCollector
        }

        onExited: {
            root.systemUnits = root.parseUnitStates(systemUnitCollector.text)
            root.systemUnitsReady = true
        }
    }

    Process {
        id: userUnitProbe
        command: [
            "systemctl",
            "--user",
            "--no-pager",
            "show",
            "--property=Id",
            "--property=LoadState",
            "--property=ActiveState",
            "--property=SubState"
        ].concat(root.kdeConnectUserUnitCandidates)

        stdout: StdioCollector {
            id: userUnitCollector
        }

        onExited: {
            root.userUnits = root.parseUnitStates(userUnitCollector.text)
            root.userUnitsReady = true
        }
    }

    Process {
        id: kdeDeviceProbe
        command: ["kdeconnect-cli", "--list-devices", "--id-only"]

        stdout: StdioCollector {
            id: kdeDeviceCollector
        }

        onExited: exitCode => {
            root.connectedKdeDeviceCount = exitCode === 0
                ? kdeDeviceCollector.text.split(/\r?\n/)
                    .filter(line => line.trim().length > 0).length
                : 0
            root.kdeDevicesReady = true
        }
    }

    Process {
        id: userServiceAction
        property string action: ""
        property string unit: ""
        command: ["systemctl", "--user", action, unit]

        onExited: exitCode => {
            root.userServiceActionStatus = exitCode === 0
                ? Translation.tr("User service updated.")
                : Translation.tr("The user-service action failed.")
            root.userUnitsReady = false
            userUnitProbe.running = true
            root.refreshKdeDevices()
        }
    }

    component IdentityCard: Rectangle {
        id: identityCard

        property string iconName: "computer"
        property string label: ""
        property string value: ""

        Layout.fillWidth: true
        Layout.preferredWidth: 340
        implicitHeight: identityContent.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        RowLayout {
            id: identityContent
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                radius: Appearance.rounding.small
                color: Appearance.colors.colSecondaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: identityCard.iconName
                    iconSize: 22
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: identityCard.label
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                StyledText {
                    Layout.fillWidth: true
                    text: identityCard.value
                    color: Appearance.colors.colOnLayer1
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }
        }
    }

    component ServiceCard: Rectangle {
        id: serviceCard

        required property var entry

        Layout.fillWidth: true
        Layout.preferredWidth: 340
        implicitHeight: serviceContent.implicitHeight + 22
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        opacity: serviceCard.entry.installed || root.refreshing ? 1 : 0.72

        RowLayout {
            id: serviceContent
            anchors.fill: parent
            anchors.margins: 11
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: Appearance.rounding.small
                color: serviceCard.entry.active
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colSecondaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: serviceCard.entry.icon
                    iconSize: 23
                    color: serviceCard.entry.active
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: serviceCard.entry.title
                        color: Appearance.colors.colOnLayer1
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        implicitWidth: stateText.implicitWidth + 14
                        implicitHeight: 24
                        radius: Appearance.rounding.full
                        color: serviceCard.entry.active
                            ? Appearance.colors.colPrimaryContainer
                            : Appearance.colors.colLayer2

                        StyledText {
                            id: stateText
                            anchors.centerIn: parent
                            text: serviceCard.entry.status
                            color: serviceCard.entry.active
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: serviceCard.entry.detail
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    SecondaryTabBar {
        Layout.fillWidth: true
        currentIndex: root.currentTab
        onCurrentIndexChanged: {
            root.currentTab = currentIndex
            root.contentY = 0
        }

        Repeater {
            model: root.tabs
            delegate: SecondaryTabButton {
                required property var modelData
                buttonIcon: modelData.icon
                buttonText: modelData.name
            }
        }
    }

    ContentSection {
        visible: root.currentTab === 0
        icon: "share"
        title: Translation.tr("Sharing")
        description: Translation.tr("Identity and local sharing capabilities")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "security"
            text: Translation.tr("This page reads service state without elevated privileges. System-wide sharing services are never changed here; managing them safely requires a narrowly scoped backend with Polkit authorization.")
        }

        ConfigRow {
            uniform: true

            IdentityCard {
                iconName: "computer"
                label: Translation.tr("Device")
                value: root.deviceIdentity
            }

            IdentityCard {
                iconName: "deployed_code"
                label: Translation.tr("Operating system")
                value: SystemInfo.distroName || Translation.tr("Unknown")
            }

            IdentityCard {
                iconName: "dns"
                label: Translation.tr("Services available")
                value: root.capabilitiesReady && root.systemUnitsReady
                    && root.userUnitsReady && root.kdeDevicesReady
                    ? Translation.tr("%1 of 5 detected").arg(root.availableServiceCount)
                    : Translation.tr("Checking…")
            }

            IdentityCard {
                iconName: "online_prediction"
                label: Translation.tr("Services active")
                value: root.capabilitiesReady && root.systemUnitsReady
                    && root.userUnitsReady && root.kdeDevicesReady
                    ? Translation.tr("%1 active").arg(root.activeServiceCount)
                    : Translation.tr("Checking…")
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            enabled: !root.refreshing && !userServiceAction.running
            materialIcon: root.refreshing ? "progress_activity" : "refresh"
            mainText: root.refreshing
                ? Translation.tr("Checking services…")
                : Translation.tr("Refresh sharing status")
            onClicked: root.refresh()
        }
    }

    ContentSection {
        visible: root.currentTab === 0
        icon: "monitor_heart"
        title: Translation.tr("Service summary")

        ConfigRow {
            uniform: true

            ServiceCard { entry: root.sshService }
            ServiceCard { entry: root.sambaService }
            ServiceCard { entry: root.avahiService }
            ServiceCard { entry: root.cupsService }
            ServiceCard { entry: root.kdeConnectService }
        }
    }

    ContentSection {
        visible: root.currentTab === 1
        icon: "lan"
        title: Translation.tr("Remote access")
        description: Translation.tr("Services that allow other computers to reach this device")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "admin_panel_settings"
            text: Translation.tr("SSH and SMB are system services. Their controls are intentionally read-only here. A future backend should expose fixed actions and let Polkit authorize each privileged change.")
        }

        ConfigRow {
            uniform: true

            ServiceCard { entry: root.sshService }
            ServiceCard { entry: root.sambaService }
        }

        ContentSubsection {
            title: Translation.tr("Connection identity")

            ConfigRow {
                uniform: true

                IdentityCard {
                    iconName: "badge"
                    label: Translation.tr("Local account")
                    value: SystemInfo.username || Translation.tr("Unknown")
                }

                IdentityCard {
                    iconName: "alternate_email"
                    label: Translation.tr("Network name")
                    value: root.avahiService.active && root.hostName.length > 0
                        ? `${root.hostName}.local`
                        : root.deviceLabel
                }
            }
        }
    }

    ContentSection {
        visible: root.currentTab === 2
        icon: "devices_other"
        title: Translation.tr("Nearby & services")
        description: Translation.tr("Discovery, device links and shared printers")

        ConfigRow {
            uniform: true

            ServiceCard { entry: root.avahiService }
            ServiceCard { entry: root.kdeConnectService }
            ServiceCard { entry: root.cupsService }
        }
    }

    ContentSection {
        visible: root.currentTab === 2
        icon: "devices"
        title: Translation.tr("KDE Connect user service")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "info"
            text: root.kdeConnectUserUnit.length > 0
                ? Translation.tr("Only this user-owned unit can be controlled here: %1").arg(root.kdeConnectUserUnit)
                : Translation.tr("KDE Connect may be D-Bus activated or started by desktop autostart. No fixed user-service unit is available to control safely.")
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                enabled: root.kdeConnectUserUnit.length > 0
                    && !root.kdeUserUnitActive && !userServiceAction.running
                materialIcon: "play_arrow"
                mainText: Translation.tr("Start")
                onClicked: root.controlKdeUserService("start")
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                enabled: root.kdeConnectUserUnit.length > 0
                    && root.kdeUserUnitActive && !userServiceAction.running
                materialIcon: "stop"
                mainText: Translation.tr("Stop")
                onClicked: root.controlKdeUserService("stop")
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                enabled: root.kdeConnectUserUnit.length > 0
                    && !userServiceAction.running
                materialIcon: "restart_alt"
                mainText: Translation.tr("Restart")
                onClicked: root.controlKdeUserService("restart")
            }
        }

        StyledText {
            visible: root.userServiceActionStatus.length > 0
            Layout.fillWidth: true
            text: root.userServiceActionStatus
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }
    }
}
