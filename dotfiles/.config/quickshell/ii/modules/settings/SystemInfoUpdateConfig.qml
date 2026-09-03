import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760
    readonly property bool settingsApp: Quickshell.env("II_SETTINGS_APP") === "1"
    property var settingsHost: null
    property int currentSubTab: 0
    property var storageRows: []
    property string storageStatus: Translation.tr("Checking storage…")
    property bool hostnameServiceAvailable: false
    property bool hostnameActionPending: false
    property bool hostnameActionError: false
    property bool hostnameFieldsDirty: false
    property bool updatingHostnameFields: false
    property string hostnameActionStatus: ""
    readonly property var tabs: [
        { name: Translation.tr("About"), icon: "info" },
        { name: Translation.tr("Storage"), icon: "hard_drive" },
        { name: Translation.tr("Updates"), icon: "system_update" },
        { name: Translation.tr("Diagnostics"), icon: "monitor_heart" }
    ]

    function applySubTab(subTab, sectionId = "") {
        root.currentSubTab = Math.max(0, Math.min(subTab, root.tabs.length - 1))
        root.contentY = 0
        if (root.currentSubTab === 1 && !storageProc.running)
            storageProc.running = true
    }

    function navigate(page, subTab = -1, sectionId = "") {
        if (root.settingsHost && typeof root.settingsHost.applyNavigation === "function")
            root.settingsHost.applyNavigation(typeof page === "string"
                ? SettingsCatalog.indexOf(page) : page, subTab, sectionId)
    }

    function flattenStorage(devices, rows = []) {
        for (const device of devices ?? []) {
            if (device.mountpoint || device.type === "disk") {
                rows.push({
                    name: device.name ?? "",
                    label: device.label ?? "",
                    type: device.type ?? "",
                    size: Number(device.size ?? 0),
                    used: Number(device.fsused ?? 0),
                    available: Number(device.fsavail ?? 0),
                    mountpoint: device.mountpoint ?? ""
                })
            }
            root.flattenStorage(device.children ?? [], rows)
        }
        return rows
    }

    function formatBytes(value) {
        const bytes = Number(value ?? 0)
        if (!isFinite(bytes) || bytes <= 0) return Translation.tr("Unknown")
        const units = ["B", "KiB", "MiB", "GiB", "TiB"]
        const exponent = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)))
        return `${(bytes / Math.pow(1024, exponent)).toFixed(exponent > 2 ? 1 : 0)} ${units[exponent]}`
    }

    property string _hostname: ""
    property string _staticHostname: ""
    property string _prettyHostname: ""
    property string _kernel: ""
    property string _cpu: ""
    property string _memory: ""
    property string _gpu: ""
    property string _uptime: ""

    function formatUptime(seconds) {
        const totalMinutes = Math.max(0, Math.floor(Number(seconds ?? 0) / 60))
        const days = Math.floor(totalMinutes / 1440)
        const hours = Math.floor((totalMinutes % 1440) / 60)
        const minutes = totalMinutes % 60
        return [
            days > 0 ? Translation.tr("%1d").arg(days) : "",
            hours > 0 ? Translation.tr("%1h").arg(hours) : "",
            Translation.tr("%1m").arg(minutes)
        ].filter(part => part.length > 0).join(" ")
    }

    function applyNativeSnapshot() {
        const snapshot = NativeSettings.snapshot ?? ({})
        const host = snapshot.host ?? ({})
        const nativeHostname = snapshot.native?.hostname ?? ({})
        const resources = snapshot.resources ?? ({})
        const memory = resources.memory ?? ({})
        root.hostnameServiceAvailable = nativeHostname.available === true
        root._staticHostname = nativeHostname.static_hostname ?? host.hostname ?? ""
        root._prettyHostname = nativeHostname.pretty_hostname ?? ""
        root._hostname = nativeHostname.hostname ?? host.hostname ?? root._staticHostname
        root._kernel = [host.kernel_name, host.kernel_release, host.architecture].filter(value => !!value).join(" ")
        root._cpu = host.cpu?.model
            ? `${host.cpu.model} · ${host.cpu.logical_count ?? "?"} ${Translation.tr("threads")}`
            : ""
        root._memory = root.formatBytes(memory.total_bytes)
        root._gpu = [host.hardware?.vendor, host.hardware?.model].filter(value => !!value).join(" ")
        root._uptime = root.formatUptime(resources.uptime_seconds)
        root.syncHostnameFields()
    }

    function syncHostnameFields(force = false) {
        if (!root.hostnameServiceAvailable)
            return
        if (!force && (root.hostnameFieldsDirty || staticHostnameInput.activeFocus
                || prettyHostnameInput.activeFocus))
            return
        root.updatingHostnameFields = true
        staticHostnameInput.text = root._staticHostname
        prettyHostnameInput.text = root._prettyHostname
        root.hostnameFieldsDirty = false
        root.updatingHostnameFields = false
    }

    function validStaticHostname(value) {
        const hostname = String(value ?? "")
        if (!hostname.length || hostname.length > 64 || !/^[\x00-\x7F]+$/.test(hostname))
            return false
        return hostname.split(".").every(label => label.length > 0 && label.length <= 63
            && /^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(label))
    }

    function validPrettyHostname(value) {
        const prettyHostname = String(value ?? "")
        return prettyHostname.length > 0
            && prettyHostname.length <= 64
            && prettyHostname.trim() === prettyHostname
            && !/[\u0000-\u001F\u007F-\u009F\u2028\u2029\u202A-\u202E\u2066-\u2069]/.test(prettyHostname)
    }

    function hostnameFieldsChanged() {
        return staticHostnameInput.text !== root._staticHostname
            || prettyHostnameInput.text !== root._prettyHostname
    }

    function hostnameValidationMessage() {
        if (staticHostnameInput.text !== root._staticHostname
                && !root.validStaticHostname(staticHostnameInput.text))
            return Translation.tr("The static hostname must be 1–64 ASCII characters in DNS-label form.")
        if (prettyHostnameInput.text !== root._prettyHostname
                && !root.validPrettyHostname(prettyHostnameInput.text))
            return Translation.tr("The device name must be 1–64 readable characters with no surrounding spaces.")
        return ""
    }

    function setHostnames() {
        const validationError = root.hostnameValidationMessage()
        if (root.hostnameActionPending || validationError.length > 0
                || !root.hostnameFieldsChanged()) {
            if (validationError.length > 0) {
                root.hostnameActionError = true
                root.hostnameActionStatus = validationError
            }
            return
        }

        const params = ({})
        if (staticHostnameInput.text !== root._staticHostname)
            params.hostname = staticHostnameInput.text
        if (prettyHostnameInput.text !== root._prettyHostname)
            params.pretty_hostname = prettyHostnameInput.text

        root.hostnameActionPending = true
        root.hostnameActionError = false
        root.hostnameActionStatus = Translation.tr("Updating device identity…")
        NativeSettings.request("hostname.set", params, (result, error) => {
            root.hostnameActionPending = false
            if (error) {
                root.hostnameActionError = true
                root.hostnameActionStatus = Translation.tr("Device identity could not be changed: %1")
                    .arg(error.message ?? Translation.tr("Unknown error"))
                NativeSettings.refresh()
                return
            }
            root.hostnameActionError = false
            root.hostnameFieldsDirty = false
            root.hostnameActionStatus = Translation.tr("Device identity updated.")
            NativeSettings.refresh()
        })
    }

    Connections {
        target: NativeSettings
        function onSnapshotChanged() { root.applyNativeSnapshot() }
    }

    Component.onCompleted: {
        root.applyNativeSnapshot()
        NativeSettings.refresh()
    }

    Process {
        id: storageProc
        command: ["lsblk", "-J", "-b", "-o", "NAME,LABEL,TYPE,SIZE,FSUSED,FSAVAIL,MOUNTPOINT"]
        stdout: StdioCollector {
            id: storageCollector
            onStreamFinished: {
                try {
                    const data = JSON.parse(storageCollector.text)
                    root.storageRows = root.flattenStorage(data.blockdevices ?? [])
                    root.storageStatus = root.storageRows.length === 0
                        ? Translation.tr("No mounted storage found")
                        : Translation.tr("%1 storage entries").arg(root.storageRows.length)
                } catch (error) {
                    root.storageRows = []
                    root.storageStatus = Translation.tr("Storage information is unavailable")
                }
            }
        }
    }

    component InfoRow: RowLayout {
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.preferredWidth: 88
            text: parent.label
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledText {
            Layout.fillWidth: true
            text: parent.value || "…"
            color: Appearance.colors.colOnLayer1
            wrapMode: Text.Wrap
        }
    }

    SecondaryTabBar {
        Layout.fillWidth: true
        currentIndex: root.currentSubTab
        onCurrentIndexChanged: root.applySubTab(currentIndex)

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
        visible: root.currentSubTab === 0
        icon: "info"
        title: Translation.tr("System info")

        InfoRow { label: Translation.tr("Host"); value: root._hostname }
        InfoRow { label: Translation.tr("Kernel"); value: root._kernel }
        InfoRow { label: Translation.tr("CPU"); value: root._cpu }
        InfoRow { label: Translation.tr("Memory"); value: root._memory }
        InfoRow { label: Translation.tr("Hardware"); value: root._gpu }
        InfoRow { label: Translation.tr("Uptime"); value: root._uptime }
        InfoRow {
            label: Translation.tr("Backend")
            value: NativeSettings.connected
                ? Translation.tr("Native service connected")
                : (NativeSettings.lastError || Translation.tr("Connecting…"))
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh system snapshot")
            enabled: NativeSettings.connected
            onClicked: NativeSettings.refresh()
        }
    }

    ContentSection {
        visible: root.currentSubTab === 0
        icon: "badge"
        title: Translation.tr("Device identity")
        description: root.hostnameServiceAvailable
            ? Translation.tr("Managed by systemd-hostnamed")
            : Translation.tr("Native hostname service unavailable")

        NoticeBox {
            Layout.fillWidth: true
            visible: !NativeSettings.connected || !root.hostnameServiceAvailable
            materialIcon: "info"
            text: !NativeSettings.connected
                ? (NativeSettings.lastError || Translation.tr("Connecting to the native settings service…"))
                : Translation.tr("systemd-hostnamed is not available, so device identity is read-only.")
        }

        ConfigRow {
            uniform: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: Translation.tr("Static hostname")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                MaterialTextField {
                    id: staticHostnameInput
                    Layout.fillWidth: true
                    maximumLength: 64
                    placeholderText: Translation.tr("workstation")
                    enabled: NativeSettings.connected && root.hostnameServiceAvailable
                        && !root.hostnameActionPending
                    onTextEdited: if (!root.updatingHostnameFields) root.hostnameFieldsDirty = true
                    onAccepted: root.setHostnames()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: Translation.tr("Device name")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                MaterialTextField {
                    id: prettyHostnameInput
                    Layout.fillWidth: true
                    maximumLength: 64
                    placeholderText: Translation.tr("My workstation")
                    enabled: NativeSettings.connected && root.hostnameServiceAvailable
                        && !root.hostnameActionPending
                    onTextEdited: if (!root.updatingHostnameFields) root.hostnameFieldsDirty = true
                    onAccepted: root.setHostnames()
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.hostnameFieldsDirty
                && root.hostnameValidationMessage().length > 0
            text: root.hostnameValidationMessage()
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "undo"
                mainText: Translation.tr("Reset fields")
                enabled: root.hostnameFieldsDirty && !root.hostnameActionPending
                onClicked: root.syncHostnameFields(true)
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "save"
                mainText: root.hostnameActionPending
                    ? Translation.tr("Saving…")
                    : Translation.tr("Save device identity")
                enabled: NativeSettings.connected && root.hostnameServiceAvailable
                    && !root.hostnameActionPending && root.hostnameFieldsChanged()
                    && root.hostnameValidationMessage().length === 0
                onClicked: root.setHostnames()
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.hostnameActionStatus.length > 0
            text: root.hostnameActionStatus
            color: root.hostnameActionError
                ? Appearance.colors.colError
                : Appearance.colors.colPrimary
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("These fields use a typed native request; Polkit may ask you to authorize the change.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        visible: root.currentSubTab === 1
        icon: "hard_drive"
        title: Translation.tr("Storage")
        description: root.storageStatus

        Repeater {
            model: root.storageRows

            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: storageRow.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                RowLayout {
                    id: storageRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    MaterialSymbol {
                        text: modelData.type === "disk" ? "hard_drive" : "folder"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.label || modelData.mountpoint || modelData.name
                            color: Appearance.colors.colOnLayer1
                            font.weight: Font.Medium
                            elide: Text.ElideMiddle
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.mountpoint || `${Translation.tr("Device")} /dev/${modelData.name}`
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            elide: Text.ElideMiddle
                        }
                    }

                    StyledText {
                        text: root.formatBytes(modelData.size)
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh storage")
            enabled: !storageProc.running
            onClicked: storageProc.running = true
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Partitioning, formatting, encryption and reset operations remain deliberately isolated because they can destroy data.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        visible: root.currentSubTab === 2
        icon: "system_update"
        title: Translation.tr("Updates")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Updates.available
                ? Translation.tr("%1 pending package updates").arg(Updates.count)
                : Translation.tr("No update helper script is configured.")
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "refresh"
                mainText: Translation.tr("Check updates")
                onClicked: Updates.refresh()
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "system_update"
                mainText: Translation.tr("Run update app")
                onClicked: Updates.launchUpdateScript()
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "info"
                mainText: Translation.tr("Open project about page")
                onClicked: Qt.openUrlExternally("https://github.com/end-4/dots-hyprland")
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 3
        icon: "monitor_heart"
        title: Translation.tr("System health")
        description: SystemHealth.healthy ? Translation.tr("No issues detected") : Translation.tr("Attention recommended")

        ConfigRow {
            uniform: true

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: healthDiskRow.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                RowLayout {
                    id: healthDiskRow
                    anchors.fill: parent
                    anchors.margins: 10
                    MaterialSymbol { text: "hard_drive"; iconSize: 22; color: Appearance.colors.colOnLayer1 }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Root disk"); color: Appearance.colors.colOnLayer1 }
                    StyledText { text: `${SystemHealth.diskPercent}%`; color: SystemHealth.diskPercent >= 90 ? Appearance.colors.colError : Appearance.colors.colSubtext }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: healthTempRow.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                RowLayout {
                    id: healthTempRow
                    anchors.fill: parent
                    anchors.margins: 10
                    MaterialSymbol { text: "device_thermostat"; iconSize: 22; color: Appearance.colors.colOnLayer1 }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Temperature"); color: Appearance.colors.colOnLayer1 }
                    StyledText { text: `${SystemHealth.temperature}°C`; color: SystemHealth.temperature >= 90 ? Appearance.colors.colError : Appearance.colors.colSubtext }
                }
            }
        }

        InfoRow { label: Translation.tr("Services"); value: Translation.tr("%1 unhealthy").arg(SystemHealth.unhealthyServices) }
        InfoRow { label: Translation.tr("Warnings"); value: `${SystemHealth.warningCount}` }
        InfoRow { label: Translation.tr("Crashes"); value: `${SystemHealth.crashCount}` }

        ConfigRow {
            uniform: true
            RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "refresh"; mainText: Translation.tr("Refresh health"); onClicked: SystemHealth.refresh() }
            RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "description"; mainText: Translation.tr("Open logs"); onClicked: SystemHealth.openLogs() }
            RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "restart_alt"; mainText: Translation.tr("Restart shell bridges"); onClicked: SystemHealth.restartBridges() }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 3
        icon: "construction"
        title: Translation.tr("Utilities & related settings")
        description: Translation.tr("Common maintenance tools and nearby settings")

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "monitor_heart"
                mainText: Translation.tr("Task manager")
                enabled: Config.options.apps.taskManager.trim().length > 0
                onClicked: Session.launchTaskManager()
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "refresh"
                mainText: Translation.tr("Check updates")
                onClicked: Updates.refresh()
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "system_update"
                mainText: Translation.tr("System update")
                onClicked: Updates.launchUpdateScript()
            }
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "volume_up"
                mainText: Translation.tr("Sound settings")
                enabled: root.settingsHost !== null
                onClicked: root.navigate("audio")
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "person"
                mainText: Translation.tr("Account settings")
                enabled: root.settingsHost !== null
                onClicked: root.navigate("accounts")
            }
        }
    }
}
