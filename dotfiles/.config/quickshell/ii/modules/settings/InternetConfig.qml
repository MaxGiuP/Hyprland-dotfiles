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
    baseWidth: 840

    property string helperScript: Quickshell.shellPath("scripts/network/network_settings_helper.sh")
    property bool wifiEnabled: false
    property bool airplaneModeEnabled: false
    property bool wifiScanning: false
    property bool snapshotLoading: false
    property int autoScanIntervalMs: 30000
    property int uiAnimationDuration: 180
    property string selectedAdapterMode: ""
    property string lastActionError: ""
    property string promptPasswordKey: ""
    property string pendingConnectKey: ""
    property string pendingConnectError: ""
    property bool extraSettingsExpanded: false
    property var cards: []
    property var wifiScanResults: []
    property var savedConnections: []
    property bool pendingWifiEnabled: false
    property bool pendingAirplaneModeEnabled: false
    property var pendingCards: []
    property var pendingWifiScanResults: []
    property var pendingSavedConnections: []
    property var expandedNetworkKeys: ({})
    property var chosenBindingsByUuid: ({})

    readonly property var sortedCards: cards.slice().sort((a, b) => {
        const typeRank = type => type === "wifi" ? 0 : type === "ethernet" ? 1 : 2
        const cardRank = card => root.cardConnected(card) ? 0 : 1
        return typeRank(a.type) - typeRank(b.type)
            || cardRank(a) - cardRank(b)
            || a.device.localeCompare(b.device)
    })
    readonly property var wifiCards: sortedCards.filter(card => card.type === "wifi")
    readonly property var ethernetCards: sortedCards.filter(card => card.type === "ethernet")
    readonly property var mainCards: sortedCards.filter(card => card.type === "wifi" || card.type === "ethernet")
    readonly property var otherCards: sortedCards.filter(card => card.type !== "wifi" && card.type !== "ethernet")
    readonly property string selectedWifiDevice: root.selectedAdapterMode.indexOf("wifi:") === 0
        ? root.selectedAdapterMode.slice(5)
        : ""
    readonly property var primaryEthernetCard: root.ethernetCards.find(card => root.cardConnected(card))
        ?? root.ethernetCards[0]
        ?? null
    readonly property var selectedWifiCard: root.selectedWifiDevice
        ? root.wifiCards.find(card => card.device === root.selectedWifiDevice) ?? null
        : null
    readonly property bool showingOverview: root.selectedAdapterMode === "overview"
    readonly property bool showingEthernet: root.selectedAdapterMode === "ethernet"
    readonly property var filteredWifiScanResults: root.showingEthernet
        ? []
        : root.selectedWifiDevice
            ? root.wifiScanResults.filter(net => net.device === root.selectedWifiDevice)
            : root.wifiScanResults
    readonly property var visibleWifiGroups: {
        const map = new Map()
        for (const entry of filteredWifiScanResults) {
            const current = map.get(entry.ssid)
            if (!current) {
                map.set(entry.ssid, {
                    ssid: entry.ssid,
                    security: entry.security,
                    entries: [entry],
                    activeEntry: entry.active ? entry : null,
                    bestEntry: entry,
                })
                continue
            }

            current.entries.push(entry)
            if (entry.active)
                current.activeEntry = entry
            if (!current.bestEntry || (entry.signal > current.bestEntry.signal))
                current.bestEntry = entry
            if (!current.security && entry.security)
                current.security = entry.security
        }

        return Array.from(map.values()).map(group => ({
            ssid: group.ssid,
            security: group.security,
            entries: group.entries.slice().sort((a, b) => (a.active === b.active ? b.signal - a.signal : (a.active ? -1 : 1))),
            activeEntry: group.activeEntry,
            bestEntry: group.activeEntry ?? group.bestEntry,
            deviceList: root.uniqueStrings(group.entries.map(entry => entry.device)),
            signal: (group.activeEntry ?? group.bestEntry)?.signal ?? 0,
            frequency: (group.activeEntry ?? group.bestEntry)?.frequency ?? 0,
            active: !!group.activeEntry,
        })).sort((a, b) => (a.active === b.active ? b.signal - a.signal : (a.active ? -1 : 1)))
    }
    readonly property var assignableProfiles: savedConnections
        .filter(profile => profile.type === "wifi" || profile.type === "ethernet")
        .sort((a, b) => {
            const rank = profile => profile.type === "wifi" ? 0 : 1
            const active = profile => profile.device.length > 0 ? 0 : 1
            return rank(a) - rank(b) || active(a) - active(b) || a.name.localeCompare(b.name)
        })
    readonly property var adapterOptions: {
        const options = []

        if (root.wifiCards.length > 0) {
            options.push({
                displayName: Translation.tr("Overview"),
                value: "overview",
                icon: "dashboard",
            })
        }

        for (const card of root.wifiCards) {
            options.push({
                displayName: `${card.device}${root.cardConnected(card) ? "  ·  " + Translation.tr("active") : ""}`,
                value: `wifi:${card.device}`,
                icon: "wifi",
            })
        }

        if (root.primaryEthernetCard) {
            options.push({
                displayName: Translation.tr("Ethernet"),
                value: "ethernet",
                icon: "lan",
            })
        }

        return options
    }

    function beginSnapshot() {
        root.pendingWifiEnabled = root.wifiEnabled
        root.pendingAirplaneModeEnabled = root.airplaneModeEnabled
        root.pendingCards = []
        root.pendingWifiScanResults = []
        root.pendingSavedConnections = []
    }

    function commitSnapshot() {
        root.wifiEnabled = root.pendingWifiEnabled
        root.airplaneModeEnabled = root.pendingAirplaneModeEnabled
        root.cards = root.pendingCards
        root.wifiScanResults = root.pendingWifiScanResults
        root.savedConnections = root.pendingSavedConnections
    }

    function uniqueStrings(values) {
        const seen = ({})
        const result = []
        for (const value of values) {
            if (!value || seen[value])
                continue
            seen[value] = true
            result.push(value)
        }
        return result
    }

    function cloneMap(source) {
        const target = ({})
        for (const key in source)
            target[key] = source[key]
        return target
    }

    function currentAdapterTitle() {
        if (root.showingOverview)
            return Translation.tr("Overview")
        if (root.showingEthernet)
            return Translation.tr("Ethernet")
        if (root.selectedWifiCard)
            return Translation.tr("Wireless adapter %1").arg(root.selectedWifiCard.device)
        return Translation.tr("Network adapter")
    }

    function currentAdapterSummary() {
        if (root.showingOverview)
            return Translation.tr("Showing all wireless adapters.")
        if (root.showingEthernet) {
            if (!root.primaryEthernetCard)
                return Translation.tr("No Ethernet card detected.")
            return root.cardConnected(root.primaryEthernetCard)
                ? Translation.tr("%1 is connected.").arg(root.primaryEthernetCard.device)
                : Translation.tr("%1 is available but not connected.").arg(root.primaryEthernetCard.device)
        }
        if (root.selectedWifiCard) {
            return root.selectedWifiCard.connection
                ? Translation.tr("%1 is currently using %2.").arg(root.selectedWifiCard.device).arg(root.selectedWifiCard.connection)
                : Translation.tr("%1 is ready to connect.").arg(root.selectedWifiCard.device)
        }
        return Translation.tr("Choose a network adapter.")
    }

    function currentAdapterStateLabel() {
        if (root.showingOverview)
            return Translation.tr("%1 cards").arg(root.wifiCards.length)
        if (root.showingEthernet)
            return root.primaryEthernetCard ? root.cardStateText(root.primaryEthernetCard) : Translation.tr("Unavailable")
        if (root.selectedWifiCard)
            return root.cardStateText(root.selectedWifiCard)
        return Translation.tr("Select an adapter")
    }

    function connectedLabel() {
        const connected = root.mainCards.filter(card => root.cardConnected(card))
        if (connected.length === 0)
            return Translation.tr("No active network link")
        if (connected.length === 1) {
            const card = connected[0]
            return card.connection
                ? Translation.tr("%1 on %2").arg(card.connection).arg(card.device)
                : Translation.tr("%1 connected").arg(card.device)
        }
        return Translation.tr("%1 active links").arg(connected.length)
    }

    function cardConnected(card) {
        return card.state.includes("(connected") || (card.state.includes("connected") && !card.state.includes("disconnected"))
    }

    function cardBusy(card) {
        return card.state.includes("connecting")
    }

    function cardStateText(card) {
        return card.state.replace(/^\d+\s*\(/, "").replace(/\)$/, "") || Translation.tr("Unknown")
    }

    function cardTypeIcon(card) {
        return card.type === "wifi"
            ? "wifi"
            : card.type === "ethernet"
                ? "lan"
                : "device_hub"
    }

    function cardTypeLabel(card) {
        return card.type === "wifi"
            ? Translation.tr("Wireless")
            : card.type === "ethernet"
                ? Translation.tr("Ethernet")
                : card.type
    }

    function wifiStrengthIcon(signal) {
        return signal > 80 ? "signal_wifi_4_bar"
            : signal > 60 ? "network_wifi_3_bar"
            : signal > 40 ? "network_wifi_2_bar"
            : signal > 20 ? "network_wifi_1_bar"
            : "signal_wifi_0_bar"
    }

    function bandLabel(frequency) {
        if (!frequency)
            return "—"
        return (frequency >= 4900 ? "5 GHz" : "2.4 GHz") + "  ·  " + frequency + " MHz"
    }

    function entryKey(entry) {
        return `${entry?.ssid ?? ""}@@${entry?.bssid ?? ""}@@${entry?.device ?? ""}`
    }

    function networkExpanded(entry) {
        return !!expandedNetworkKeys[entryKey(entry)]
    }

    function setNetworkExpanded(entry, expanded) {
        const next = root.cloneMap(expandedNetworkKeys)
        next[entryKey(entry)] = expanded
        expandedNetworkKeys = next
    }

    function selectedEntryForGroup(group) {
        return group.activeEntry
            ?? group.bestEntry
            ?? group.entries[0]
            ?? null
    }

    function hasSavedWifiProfile(group) {
        return root.savedConnections.some(profile => profile.type === "wifi" && profile.name === (group?.ssid ?? ""))
    }

    function profileChoices(profile) {
        const cardsForProfile = profile.type === "wifi" ? wifiCards : ethernetCards
        return [
            {
                displayName: Translation.tr("Any compatible card"),
                value: "",
                icon: "device_hub",
            },
        ].concat(cardsForProfile.map(card => ({
                displayName: `${card.device}${card.connection === profile.name ? "  ·  " + Translation.tr("active") : ""}`,
                value: card.device,
                icon: root.cardTypeIcon(card),
            })))
    }

    function profileSelectedBinding(profile) {
        if (chosenBindingsByUuid[profile.uuid] !== undefined)
            return chosenBindingsByUuid[profile.uuid]
        return profile.boundInterface ?? ""
    }

    function setProfileBinding(profile, device) {
        const next = root.cloneMap(chosenBindingsByUuid)
        next[profile.uuid] = device
        chosenBindingsByUuid = next
    }

    function handleSnapshotLine(line) {
        const parts = line.split("\t")
        if (parts.length < 2)
            return

        switch (parts[0]) {
        case "RADIO":
            if (parts[1] === "wifi")
                root.pendingWifiEnabled = parts[2] === "1"
            else if (parts[1] === "airplane")
                root.pendingAirplaneModeEnabled = parts[2] === "1"
            break
        case "CARD":
            root.pendingCards = root.pendingCards.concat([{
                device: parts[1] ?? "",
                type: parts[2] ?? "",
                state: parts[3] ?? "",
                connection: parts[4] ?? "",
                hwaddr: parts[5] ?? "",
                ip: parts[6] ?? "",
                gateway: parts[7] ?? "",
                dns: parts[8] ?? "",
            }])
            break
        case "WIFI":
            root.pendingWifiScanResults = root.pendingWifiScanResults.concat([{
                ssid: parts[1] ?? "",
                bssid: parts[2] ?? "",
                device: parts[3] ?? "",
                signal: parseInt(parts[4] ?? "0"),
                frequency: parseInt(parts[5] ?? "0"),
                security: parts[6] ?? "",
                active: (parts[7] ?? "0") === "1",
            }])
            break
        case "PROFILE":
            root.pendingSavedConnections = root.pendingSavedConnections.concat([{
                uuid: parts[1] ?? "",
                name: parts[2] ?? "",
                type: parts[3] ?? "",
                device: parts[4] ?? "",
                boundInterface: parts[5] ?? "",
                autoconnect: parts[6] === "yes",
            }])
            break
        }
    }

    function refreshSnapshot() {
        if (snapshotProc.running)
            return
        root.lastActionError = ""
        root.snapshotLoading = true
        root.beginSnapshot()
        snapshotProc.running = true
    }

    function requestAutoScan() {
        if (!root.wifiEnabled || snapshotProc.running || actionProc.running || connectProc.running || assignProc.running)
            return
        root.runAction(["rescan-wifi"], true)
    }

    function runAction(args, markScanning = false) {
        if (actionProc.running || connectProc.running || assignProc.running)
            return
        root.lastActionError = ""
        root.pendingConnectError = ""
        if (markScanning)
            root.wifiScanning = true
        actionProc.exec(["bash", root.helperScript].concat(args))
    }

    function connectGroup(group, password) {
        const entry = selectedEntryForGroup(group)
        if (!entry || connectProc.running)
            return

        root.lastActionError = ""
        root.pendingConnectError = ""
        root.pendingConnectKey = entryKey(entry)
        connectProc.exec([
            "bash",
            root.helperScript,
            "connect-wifi",
            entry.ssid,
            entry.bssid,
            entry.device,
            password ?? "",
        ])
    }

    function saveProfileBinding(profile) {
        if (assignProc.running)
            return
        assignProc.exec([
            "bash",
            root.helperScript,
            "assign-connection",
            profile.uuid,
            profileSelectedBinding(profile),
        ])
    }

    function ensureValidSelection() {
        const values = root.adapterOptions.map(option => option.value)
        if (root.selectedAdapterMode.length > 0 && values.includes(root.selectedAdapterMode))
            return
        root.selectedAdapterMode = root.adapterOptions[0]?.value ?? ""
    }

    Component.onCompleted: root.refreshSnapshot()

    Timer {
        interval: root.autoScanIntervalMs
        repeat: true
        running: root.wifiEnabled
        triggeredOnStart: false
        onTriggered: root.requestAutoScan()
    }

    Process {
        id: snapshotProc
        command: ["bash", root.helperScript, "snapshot"]
        stdout: SplitParser {
            onRead: line => root.handleSnapshotLine(line)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root.lastActionError = text.trim()
            }
        }
        onExited: exitCode => {
            if (exitCode === 0)
                root.commitSnapshot()
            root.snapshotLoading = false
            root.wifiScanning = false
            root.ensureValidSelection()
        }
    }

    Process {
        id: actionProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root.lastActionError = text.trim()
            }
        }
        onExited: exitCode => {
            root.wifiScanning = false
            if (exitCode === 0)
                root.refreshSnapshot()
        }
    }

    Process {
        id: assignProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root.lastActionError = text.trim()
            }
        }
        onExited: exitCode => {
            if (exitCode === 0)
                root.refreshSnapshot()
        }
    }

    Process {
        id: connectProc
        stderr: SplitParser {
            onRead: line => {
                if (line.includes("Secrets were required") || line.includes("No secrets"))
                    root.promptPasswordKey = root.pendingConnectKey
                root.pendingConnectError = line
                root.lastActionError = line
            }
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.promptPasswordKey = ""
                root.pendingConnectError = ""
                root.lastActionError = ""
                root.refreshSnapshot()
            } else if (!root.promptPasswordKey) {
                root.lastActionError = root.pendingConnectError || Translation.tr("Could not connect to that network.")
            }
        }
    }

    component DetailPair: RowLayout {
        property string dlabel: ""
        property string dvalue: ""
        property bool mono: false
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.preferredWidth: 90
            text: parent.dlabel
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledText {
            Layout.fillWidth: true
            text: parent.dvalue || "—"
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: parent.mono ? Appearance.font.family.monospace : Appearance.font.family.main
            wrapMode: Text.WrapAnywhere
        }
    }

    component StatusChip: Rectangle {
        property string label: ""
        property color chipColor: Appearance.colors.colLayer2
        property color textColor: Appearance.colors.colOnLayer1

        radius: Appearance.rounding.full
        color: chipColor
        implicitWidth: chipLabel.implicitWidth + 18
        implicitHeight: chipLabel.implicitHeight + 8

        StyledText {
            id: chipLabel
            anchors.centerIn: parent
            text: parent.label
            color: parent.textColor
            font.pixelSize: Appearance.font.pixelSize.smaller
            animateChange: true
            animationDistanceY: 3
        }

        Behavior on color { ColorAnimation { duration: root.uiAnimationDuration } }
        Behavior on border.color { ColorAnimation { duration: root.uiAnimationDuration } }
        Behavior on opacity {
            NumberAnimation { duration: root.uiAnimationDuration; easing.type: Easing.OutCubic }
        }
    }

    ContentSection {
        icon: root.wifiEnabled ? "wifi" : "wifi_off"
        title: Translation.tr("Internet")

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: root.airplaneModeEnabled ? "flight" : "flight_takeoff"
                text: Translation.tr("Airplane mode")
                checked: root.airplaneModeEnabled
                onClicked: root.runAction(["toggle-airplane", root.airplaneModeEnabled ? "off" : "on"])
            }

            ConfigSwitch {
                buttonIcon: root.wifiEnabled ? "wifi" : "wifi_off"
                text: root.wifiEnabled ? Translation.tr("Wireless on") : Translation.tr("Wireless off")
                checked: root.wifiEnabled
                enabled: !root.airplaneModeEnabled
                onClicked: root.runAction(["toggle-wifi", root.wifiEnabled ? "off" : "on"])
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: root.wifiScanning ? "radar" : "refresh"
                mainText: root.wifiScanning ? Translation.tr("Scanning…") : Translation.tr("Scan networks")
                enabled: root.wifiEnabled && !root.wifiScanning && !actionProc.running
                onClicked: root.runAction(["rescan-wifi"], true)
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "refresh"
                mainText: Translation.tr("Refresh now")
                enabled: !snapshotProc.running
                onClicked: root.refreshSnapshot()
            }
        }

        StyledComboBox {
            Layout.fillWidth: true
            buttonIcon: "router"
            textRole: "displayName"
            model: root.adapterOptions
            currentIndex: Math.max(0, model.findIndex(item => item.value === root.selectedAdapterMode))
            onActivated: index => {
                root.selectedAdapterMode = model[index]?.value ?? ""
                root.promptPasswordKey = ""
                root.pendingConnectKey = ""
            }
        }

        Rectangle {
            Layout.fillWidth: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
            implicitHeight: summaryColumn.implicitHeight + 20

            ColumnLayout {
                id: summaryColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: root.showingOverview
                            ? "dashboard"
                            : root.showingEthernet
                            ? "lan"
                            : root.selectedWifiCard
                                ? "wifi"
                                : "auto_awesome"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: root.currentAdapterTitle()
                            color: Appearance.colors.colOnLayer1
                            font.weight: Font.Medium
                            animateChange: true
                            animationDistanceY: 4
                        }

                        StyledText {
                            text: root.currentAdapterSummary()
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            animateChange: true
                            animationDistanceY: 4
                        }
                    }

                    StatusChip {
                        label: root.currentAdapterStateLabel()
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: width > 720 ? 2 : 1
                    columnSpacing: 24
                    rowSpacing: 4

                    DetailPair {
                        dlabel: Translation.tr("Connection")
                        dvalue: root.showingOverview
                            ? root.connectedLabel()
                            : root.showingEthernet
                            ? (root.primaryEthernetCard?.connection ?? "")
                            : (root.selectedWifiCard?.connection ?? root.connectedLabel())
                    }
                    DetailPair {
                        visible: !root.showingOverview
                        dlabel: Translation.tr("IP Address")
                        dvalue: root.showingEthernet
                            ? (root.primaryEthernetCard?.ip ?? "")
                            : (root.selectedWifiCard?.ip ?? "")
                        mono: true
                    }
                    DetailPair {
                        visible: !root.showingOverview
                        dlabel: Translation.tr("Gateway")
                        dvalue: root.showingEthernet
                            ? (root.primaryEthernetCard?.gateway ?? "")
                            : (root.selectedWifiCard?.gateway ?? "")
                        mono: true
                    }
                    DetailPair {
                        visible: !root.showingOverview
                        dlabel: Translation.tr("DNS")
                        dvalue: root.showingEthernet
                            ? (root.primaryEthernetCard?.dns ?? "")
                            : (root.selectedWifiCard?.dns ?? "")
                        mono: true
                    }
                }

                Revealer {
                    Layout.fillWidth: true
                    reveal: root.showingOverview && root.wifiCards.length > 0
                    vertical: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: root.wifiCards

                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8

                                MaterialSymbol {
                                    text: "wifi"
                                    iconSize: 18
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledText {
                                    Layout.preferredWidth: 88
                                    text: modelData.device
                                    color: Appearance.colors.colOnLayer1
                                    font.family: Appearance.font.family.monospace
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.connection || root.cardStateText(modelData)
                                    color: Appearance.colors.colSubtext
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }

                                StatusChip {
                                    label: root.cardStateText(modelData)
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StatusChip {
                        label: root.wifiEnabled ? Translation.tr("Wireless enabled") : Translation.tr("Wireless disabled")
                        chipColor: root.wifiEnabled ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                        textColor: root.wifiEnabled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                    }

                    StatusChip {
                        label: Translation.tr("%1 cards").arg(root.mainCards.length)
                    }

                    StatusChip {
                        visible: root.snapshotLoading
                        label: Translation.tr("Refreshing")
                        chipColor: Appearance.colors.colSecondaryContainer
                        textColor: Appearance.colors.colOnSecondaryContainer
                    }

                    Item { Layout.fillWidth: true }

                    DialogButton {
                        visible: root.showingEthernet && !!root.primaryEthernetCard && (root.cardConnected(root.primaryEthernetCard) || root.cardBusy(root.primaryEthernetCard))
                        buttonText: Translation.tr("Disconnect")
                        enabled: !actionProc.running
                        onClicked: root.runAction(["disconnect-device", root.primaryEthernetCard.device])
                    }

                    DialogButton {
                        visible: root.showingEthernet && !!root.primaryEthernetCard && !root.cardConnected(root.primaryEthernetCard) && !root.cardBusy(root.primaryEthernetCard)
                        buttonText: Translation.tr("Connect")
                        enabled: !actionProc.running
                        onClicked: root.runAction(["connect-device", root.primaryEthernetCard.device])
                    }
                }
            }
        }

        StyledText {
            visible: opacity > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colError
            text: root.lastActionError
            opacity: root.lastActionError.length > 0 ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.uiAnimationDuration; easing.type: Easing.OutCubic }
            }
        }
    }

    ContentSection {
        visible: root.wifiCards.length > 0 && !root.showingEthernet
        icon: "network_wifi"
        title: Translation.tr("Available networks")

        StyledListView {
            Layout.fillWidth: true
            implicitHeight: contentHeight
            interactive: false
            clip: false
            spacing: 8
            animateMovement: true
            model: root.visibleWifiGroups

            delegate: Rectangle {
                id: netCard
                required property var modelData
                readonly property var selectedEntry: root.selectedEntryForGroup(modelData)
                readonly property string selectedEntryKey: root.entryKey(selectedEntry)
                readonly property bool knownLockedNetwork: !!(selectedEntry?.security) && root.hasSavedWifiProfile(modelData)
                readonly property bool connecting: connectProc.running && root.pendingConnectKey === selectedEntryKey
                property bool expanded: false
                width: ListView.view?.width ?? 0
                radius: Appearance.rounding.normal
                color: modelData.active
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                implicitHeight: netColumn.implicitHeight + 18
                opacity: 1
                scale: 1

                Behavior on color { ColorAnimation { duration: root.uiAnimationDuration } }
                Behavior on border.color { ColorAnimation { duration: root.uiAnimationDuration } }
                Behavior on implicitHeight {
                    NumberAnimation { duration: root.uiAnimationDuration; easing.type: Easing.OutCubic }
                }

                ColumnLayout {
                    id: netColumn
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: root.wifiStrengthIcon(netCard.selectedEntry?.signal ?? 0)
                            iconSize: 20
                            color: modelData.active
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnLayer1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: modelData.ssid
                                color: modelData.active
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }

                            StyledText {
                                text: root.selectedWifiCard
                                    ? root.bandLabel(netCard.selectedEntry?.frequency ?? 0)
                                    : Translation.tr("Using %1").arg(netCard.selectedEntry?.device ?? "")
                                color: modelData.active
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }

                        Item {
                            Layout.minimumWidth: 64
                            Layout.preferredWidth: 64
                            Layout.maximumWidth: 64
                            Layout.alignment: Qt.AlignVCenter
                            implicitHeight: 28

                            StatusChip {
                                anchors.centerIn: parent
                                label: `${netCard.selectedEntry?.signal ?? 0}%`
                                chipColor: Appearance.colors.colLayer2
                                textColor: Appearance.colors.colOnLayer1
                            }
                        }

                        Item {
                            Layout.minimumWidth: 20
                            Layout.preferredWidth: 20
                            Layout.maximumWidth: 20
                            Layout.alignment: Qt.AlignVCenter
                            implicitHeight: 20

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: !!(netCard.selectedEntry?.security)
                                text: netCard.knownLockedNetwork ? "key" : "lock"
                                iconSize: 14
                                color: netCard.knownLockedNetwork
                                    ? Appearance.colors.colPrimary
                                    : modelData.active
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colSubtext
                            }
                        }

                        Item {
                            Layout.minimumWidth: 112
                            Layout.preferredWidth: 112
                            Layout.maximumWidth: 112
                            Layout.alignment: Qt.AlignVCenter
                            implicitHeight: 36

                            MaterialLoadingIndicator {
                                anchors.centerIn: parent
                                visible: netCard.connecting
                                loading: netCard.connecting
                                implicitSize: 28
                            }

                            DialogButton {
                                anchors.fill: parent
                                visible: !netCard.connecting
                                buttonText: netCard.selectedEntry?.active
                                    ? Translation.tr("Disconnect")
                                    : Translation.tr("Connect")
                                enabled: !connectProc.running && !actionProc.running && !!netCard.selectedEntry
                                onClicked: {
                                    if (netCard.selectedEntry?.active)
                                        root.runAction(["disconnect-device", netCard.selectedEntry.device])
                                    else
                                        root.connectGroup(netCard.modelData, "")
                                }
                            }
                        }

                        RippleButton {
                            Layout.minimumWidth: 34
                            Layout.preferredWidth: 34
                            Layout.maximumWidth: 34
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 34
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            onClicked: netCard.expanded = !netCard.expanded

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: netCard.expanded ? "expand_less" : "expand_more"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }

                    Revealer {
                        Layout.fillWidth: true
                        reveal: netCard.expanded
                        vertical: true

                        ColumnLayout {
                            width: parent.width
                            spacing: 6

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width > 720 ? 2 : 1
                                columnSpacing: 24
                                rowSpacing: 4

                                DetailPair { dlabel: Translation.tr("Card"); dvalue: netCard.selectedEntry?.device ?? ""; mono: true }
                                DetailPair { dlabel: Translation.tr("Band"); dvalue: root.bandLabel(netCard.selectedEntry?.frequency ?? 0) }
                                DetailPair { dlabel: Translation.tr("Security"); dvalue: netCard.selectedEntry?.security || Translation.tr("Open") }
                                DetailPair { dlabel: "BSSID"; dvalue: netCard.selectedEntry?.bssid ?? ""; mono: true }
                            }

                            StyledText {
                                visible: !root.selectedWifiCard && netCard.modelData.deviceList.length > 1
                                Layout.fillWidth: true
                                text: Translation.tr("Also visible on %1").arg(netCard.modelData.deviceList.filter(device => device !== (netCard.selectedEntry?.device ?? "")).join(", "))
                                color: netCard.modelData.active
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colSubtext
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }

                    Revealer {
                        Layout.fillWidth: true
                        reveal: root.promptPasswordKey === netCard.selectedEntryKey
                        vertical: true

                        ColumnLayout {
                            width: parent.width
                            spacing: 6

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Password required for %1 on %2").arg(netCard.selectedEntry?.ssid ?? "").arg(netCard.selectedEntry?.device ?? "")
                                color: modelData.active
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colSubtext
                                wrapMode: Text.Wrap
                            }

                            MaterialTextField {
                                id: passwordField
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Network password")
                                echoMode: TextInput.Password
                                inputMethodHints: Qt.ImhSensitiveData
                                onAccepted: root.connectGroup(netCard.modelData, text)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }

                                DialogButton {
                                    buttonText: Translation.tr("Cancel")
                                    onClicked: root.promptPasswordKey = ""
                                }

                                DialogButton {
                                    buttonText: Translation.tr("Connect")
                                    enabled: passwordField.text.length > 0 && !connectProc.running
                                    onClicked: root.connectGroup(netCard.modelData, passwordField.text)
                                }
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            visible: opacity > 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colSubtext
            text: Translation.tr("Enable wireless to browse nearby networks.")
            opacity: !root.wifiEnabled ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.uiAnimationDuration; easing.type: Easing.OutCubic }
            }
        }

        StyledText {
            visible: opacity > 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colSubtext
            text: root.selectedWifiCard
                ? Translation.tr("No networks were found for %1.").arg(root.selectedWifiCard.device)
                : Translation.tr("No visible networks were found.")
            opacity: root.wifiEnabled && root.visibleWifiGroups.length === 0 && !root.snapshotLoading ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.uiAnimationDuration; easing.type: Easing.OutCubic }
            }
        }
    }

    ContentSection {
        icon: "expand_content"
        title: Translation.tr("Extra settings")

        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 42
            buttonRadius: Appearance.rounding.normal
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            onClicked: root.extraSettingsExpanded = !root.extraSettingsExpanded

            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                MaterialSymbol {
                    text: root.extraSettingsExpanded ? "expand_less" : "expand_more"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Show card details, saved bindings, and tools")
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        Revealer {
            Layout.fillWidth: true
            reveal: root.extraSettingsExpanded
            vertical: true

            ColumnLayout {
                width: parent.width
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: extraCardColumn.implicitHeight + 18
                    Behavior on implicitHeight {
                        NumberAnimation { duration: root.uiAnimationDuration; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        id: extraCardColumn
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Detected network cards")
                            color: Appearance.colors.colOnLayer1
                            font.weight: Font.Medium
                        }

                        Repeater {
                            model: root.mainCards

                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8

                                MaterialSymbol {
                                    text: root.cardTypeIcon(modelData)
                                    iconSize: 18
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledText {
                                    Layout.preferredWidth: 88
                                    text: modelData.device
                                    color: Appearance.colors.colOnLayer1
                                    font.family: Appearance.font.family.monospace
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.connection || root.cardStateText(modelData)
                                    color: Appearance.colors.colSubtext
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }

                                StatusChip {
                                    label: root.cardStateText(modelData)
                                }
                            }
                        }

                        StyledText {
                            visible: root.otherCards.length > 0
                            Layout.fillWidth: true
                            text: Translation.tr("%1 additional virtual or auxiliary interfaces are present but hidden from the main view.").arg(root.otherCards.length)
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: bindingsColumn.implicitHeight + 18
                    Behavior on implicitHeight {
                        NumberAnimation { duration: root.uiAnimationDuration; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        id: bindingsColumn
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 8

                    StyledText {
                        text: Translation.tr("Saved connection bindings")
                        color: Appearance.colors.colOnLayer1
                        font.weight: Font.Medium
                    }

                    Repeater {
                        model: root.assignableProfiles

                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                MaterialSymbol {
                                    text: modelData.type === "wifi" ? "wifi" : "lan"
                                    iconSize: 16
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: Appearance.colors.colOnLayer1
                                    font.weight: Font.Medium
                                }

                                StatusChip {
                                    label: modelData.type === "wifi" ? Translation.tr("Wireless") : Translation.tr("Ethernet")
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                StyledComboBox {
                                    Layout.fillWidth: true
                                    buttonIcon: "router"
                                    textRole: "displayName"
                                    model: root.profileChoices(modelData)
                                    currentIndex: Math.max(0, model.findIndex(item => item.value === root.profileSelectedBinding(modelData)))
                                    onActivated: index => root.setProfileBinding(modelData, model[index]?.value ?? "")
                                }

                                DialogButton {
                                    buttonText: Translation.tr("Save")
                                    enabled: !assignProc.running
                                    onClicked: root.saveProfileBinding(modelData)
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: root.assignableProfiles.length === 0
                        Layout.fillWidth: true
                        text: Translation.tr("No saved network connections were found.")
                        color: Appearance.colors.colSubtext
                        horizontalAlignment: Text.AlignHCenter
                    }
                    }
                }

                ConfigRow {
                    uniform: true

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "settings"
                        mainText: Translation.tr("Open network settings")
                        onClicked: Quickshell.execDetached(["bash", "-lc", Config.options.apps.network])
                    }

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "settings_ethernet"
                        mainText: Translation.tr("Open ethernet settings")
                        onClicked: Quickshell.execDetached(["bash", "-lc", Config.options.apps.networkEthernet])
                    }

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "open_in_browser"
                        mainText: Translation.tr("Open captive portal test")
                        onClicked: Network.openPublicWifiPortal()
                    }
                }
            }
        }
    }
}
