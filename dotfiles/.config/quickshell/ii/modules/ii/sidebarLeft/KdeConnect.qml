import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root
    property var devices: KdeConnectService.devices
    property var phoneNotifications: KdeConnectService.phoneNotifications
    property string lastError: KdeConnectService.lastError
    property string sharePath: ""
    property string pendingStoragePath: ""
    property string pendingStorageDeviceId: ""
    property string pendingSharePath: ""
    property string pendingShareDeviceId: ""

    function refresh() { KdeConnectService.refresh() }
    function runAction(args) { KdeConnectService.runAction(args) }

    function openStorageOrMount(deviceId, mountPoint) {
        root.pendingStorageDeviceId = deviceId || "";
        root.pendingStoragePath = mountPoint || "";
        if (root.pendingStoragePath.length === 0) {
            root.runAction(["--device", root.pendingStorageDeviceId, "--mount"]);
            return;
        }
        storagePathCheck.running = false;
        storagePathCheck.command = ["test", "-d", root.pendingStoragePath];
        storagePathCheck.running = true;
    }

    function sendFile(deviceId, filePath) {
        root.pendingShareDeviceId = deviceId || "";
        root.pendingSharePath = (filePath || "").trim();
        if (root.pendingShareDeviceId.length === 0 || root.pendingSharePath.length === 0) return;
        sharePathCheck.running = false;
        sharePathCheck.command = ["test", "-e", root.pendingSharePath];
        sharePathCheck.running = true;
    }

    function batteryColor(pct) {
        if (pct < 0) return Appearance.colors.colSubtext;
        if (pct < 20) return Appearance.colors.colError;
        if (pct < 40) return Qt.rgba(1, 0.6, 0, 1);
        return Appearance.colors.colPrimary;
    }

    function deviceGlyph(modelData) {
        const type = (modelData.type ?? "").toLowerCase();
        if (type.indexOf("tablet") !== -1) return "tablet_android";
        if (type.indexOf("laptop") !== -1) return "laptop_mac";
        if (type.indexOf("desktop") !== -1) return "desktop_windows";
        return "smartphone";
    }

    function parseNotif(s) {
        if (s.startsWith("- ")) s = s.slice(2).trim();
        const sep = s.indexOf(": ");
        if (sep >= 0) return { app: s.slice(0, sep).trim(), msg: s.slice(sep + 2).trim() };
        return { app: "", msg: s };
    }

    function deviceNotificationsFor(device) {
        const deviceId = `${device?.id ?? ""}`;
        const deviceName = `${device?.name ?? ""}`;

        const byId = root.phoneNotifications.filter(notif => `${notif?.deviceId ?? ""}` === deviceId);
        if (byId.length > 0)
            return byId;

        const byName = root.phoneNotifications.filter(notif => `${notif?.deviceName ?? ""}` === deviceName);
        if (byName.length > 0)
            return byName;

        if ((device?.notificationCount ?? 0) > 0 && root.phoneNotifications.length > 0)
            return root.phoneNotifications;

        const availableDevices = root.devices.filter(d => d?.available);
        if (root.phoneNotifications.length > 0 && device?.available) {
            const firstAvailable = availableDevices[0];
            if (!firstAvailable || firstAvailable?.id === device?.id)
                return root.phoneNotifications;
        }

        return (device?.notifications ?? []).map(raw => {
            const parsed = root.parseNotif(`${raw ?? ""}`);
            return {
                deviceId,
                deviceName,
                appName: parsed.app,
                ticker: parsed.msg.length > 0 ? parsed.msg : `${raw ?? ""}`,
            };
        });
    }

    function mprisCmd(deviceId, method, extra) {
        const path = `/modules/kdeconnect/devices/${deviceId}/mprisremote`;
        const iface = "org.kde.kdeconnect.device.mprisremote";
        const cmd = ["qdbus", "org.kde.kdeconnect", path, `${iface}.${method}`];
        return extra ? cmd.concat(extra) : cmd;
    }

    Process {
        id: filePickerProc
        command: ["kdialog", "--getopenfilename", Quickshell.env("HOME") || "/"]
        stdout: StdioCollector { id: filePickerOut; waitForEnd: true }
        onExited: exitCode => {
            if (exitCode === 0 && filePickerOut.text.trim().length > 0)
                root.sharePath = filePickerOut.text.trim();
        }
    }

    Process {
        id: storagePathCheck
        onExited: exitCode => {
            if (exitCode === 0 && root.pendingStoragePath.length > 0)
                Qt.openUrlExternally(`file://${root.pendingStoragePath}`);
            else if (root.pendingStorageDeviceId.length > 0)
                root.runAction(["--device", root.pendingStorageDeviceId, "--mount"]);
        }
    }

    Process {
        id: sharePathCheck
        onExited: exitCode => {
            if (exitCode === 0 && root.pendingShareDeviceId.length > 0 && root.pendingSharePath.length > 0)
                root.runAction(["--device", root.pendingShareDeviceId, "--share", root.pendingSharePath]);
            else
                KdeConnectService.lastError = Translation.tr("File not found: %1").arg(root.pendingSharePath);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        StyledText {
            visible: root.lastError.length > 0
            text: root.lastError
            color: Appearance.colors.colError
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: devicesColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: devicesColumn
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 10

                Repeater {
                    model: root.devices

                    delegate: Rectangle {
                        id: deviceCard
                        required property var modelData
                        property string keyPayload: ""
                        property bool deviceAvailable: modelData.available
                        property string deviceId: modelData.id
                        Layout.fillWidth: true
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer2
                        border.width: 1
                        border.color: modelData.available
                            ? Qt.alpha(Appearance.colors.colPrimary, 0.3)
                            : Appearance.colors.colLayer3
                        implicitHeight: cardColumn.implicitHeight + 20

                        property var kdePlayerList: []
                        property string kdeCurrentPlayer: ""
                        property string kdeRequestedPlayer: ""
                        property bool currentPlayerResolved: false

                        function normalizePlayerKey(value) {
                            return `${value ?? ""}`.toLowerCase().replace(/[^a-z0-9]+/g, "");
                        }

                        function playerForSource(playerName) {
                            const target = normalizePlayerKey(playerName);
                            if (target.length === 0)
                                return null;

                            const kdePlayers = MprisController.players.filter(
                                p => (p?.dbusName ?? "").toLowerCase().includes("kdeconnect"));

                            const candidates = kdePlayers.map(player => ({
                                player,
                                keys: [
                                    normalizePlayerKey(player?.identity),
                                    normalizePlayerKey(player?.desktopEntry),
                                    normalizePlayerKey(player?.dbusName),
                                    normalizePlayerKey(player?.trackTitle),
                                    normalizePlayerKey(player?.trackArtist)
                                ]
                            }));

                            for (const candidate of candidates) {
                                if (candidate.keys.some(key => key.length > 0 && (key === target || key.includes(target) || target.includes(key))))
                                    return candidate.player;
                            }

                            return null;
                        }

                        function activatePlayer(playerName) {
                            if (typeof playerName !== "string" || playerName.length === 0)
                                return;
                            if (playerName === deviceCard.kdeCurrentPlayer && deviceCard.kdeRequestedPlayer.length === 0)
                                return;
                            deviceCard.kdeRequestedPlayer = playerName;
                            deviceCard.kdeCurrentPlayer = playerName;
                            Quickshell.execDetached([
                                "dbus-send", "--session",
                                "--dest=org.kde.kdeconnect",
                                `/modules/kdeconnect/devices/${deviceCard.deviceId}/mprisremote`,
                                "org.freedesktop.DBus.Properties.Set",
                                "string:org.kde.kdeconnect.device.mprisremote",
                                "string:player",
                                `variant:string:${playerName}`
                            ]);
                            playerSwitchGuard.restart();
                            playerRefreshTimer.restart();
                        }

                        function runPlayerCommand(playerName, method, extra) {
                            activatePlayer(playerName);
                            Quickshell.execDetached(root.mprisCmd(deviceCard.deviceId, method, extra ?? null));
                        }

                        function refreshPlayerList() {
                            playerListProc.running = false
                            playerListProc.running = true
                            currentPlayerProc.running = false
                            currentPlayerProc.running = true
                        }

                        Process {
                            id: playerListProc
                            property var _collected: []
                            command: ["qdbus", "org.kde.kdeconnect",
                                      `/modules/kdeconnect/devices/${deviceCard.deviceId}/mprisremote`,
                                      "org.kde.kdeconnect.device.mprisremote.playerList"]
                            stdout: SplitParser {
                                onRead: data => {
                                    const t = data.trim()
                                    if (t.length > 0)
                                        playerListProc._collected.push(t)
                                }
                            }
                            onExited: {
                                deviceCard.kdePlayerList = playerListProc._collected.slice()
                                if (deviceCard.kdePlayerList.length > 0 && deviceCard.kdePlayerList.indexOf(deviceCard.kdeCurrentPlayer) === -1)
                                    deviceCard.kdeCurrentPlayer = deviceCard.kdePlayerList[0]
                                playerListProc._collected = []
                            }
                        }

                        Process {
                            id: currentPlayerProc
                            property string _result: ""
                            command: ["qdbus", "org.kde.kdeconnect",
                                      `/modules/kdeconnect/devices/${deviceCard.deviceId}/mprisremote`,
                                      "org.kde.kdeconnect.device.mprisremote.player"]
                            stdout: SplitParser {
                                onRead: data => {
                                    const t = data.trim()
                                    if (t.length > 0)
                                        currentPlayerProc._result = t
                                }
                            }
                            onExited: {
                                deviceCard.currentPlayerResolved = true
                                if (currentPlayerProc._result.length > 0) {
                                    if (deviceCard.kdeRequestedPlayer.length > 0
                                            && currentPlayerProc._result !== deviceCard.kdeRequestedPlayer
                                            && playerSwitchGuard.running) {
                                        currentPlayerProc._result = ""
                                        return
                                    }
                                    deviceCard.kdeCurrentPlayer = currentPlayerProc._result
                                    if (currentPlayerProc._result === deviceCard.kdeRequestedPlayer) {
                                        deviceCard.kdeRequestedPlayer = ""
                                        playerSwitchGuard.stop()
                                    }
                                } else if (deviceCard.kdePlayerList.length > 0 && deviceCard.kdeCurrentPlayer.length === 0) {
                                    deviceCard.kdeCurrentPlayer = deviceCard.kdePlayerList[0]
                                }
                                currentPlayerProc._result = ""
                            }
                        }

                        Timer {
                            id: playerSwitchGuard
                            interval: 1800
                            repeat: false
                            onTriggered: deviceCard.kdeRequestedPlayer = ""
                        }

                        Timer {
                            id: playerRefreshTimer
                            interval: 350
                            repeat: false
                            onTriggered: deviceCard.refreshPlayerList()
                        }

                        Timer {
                            interval: 5000
                            running: deviceCard.deviceAvailable
                            repeat: true
                            onTriggered: deviceCard.refreshPlayerList()
                            Component.onCompleted: {
                                if (deviceCard.deviceAvailable)
                                    deviceCard.refreshPlayerList()
                            }
                        }

                        ColumnLayout {
                            id: cardColumn
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            // ── Header: icon + name + status + refresh ──
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Rectangle {
                                    implicitWidth: 40
                                    implicitHeight: 40
                                    radius: 20
                                    color: modelData.available
                                        ? Appearance.colors.colPrimaryContainer
                                        : Appearance.colors.colLayer3

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: root.deviceGlyph(modelData)
                                        iconSize: 20
                                        color: modelData.available
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colOnLayer3
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        spacing: 6

                                        MaterialSymbol {
                                            text: modelData.available ? "wifi" : "wifi_off"
                                            iconSize: 13
                                            color: modelData.available
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colSubtext
                                        }

                                        StyledText {
                                            text: modelData.available
                                                ? Translation.tr("Online")
                                                : Translation.tr("Offline")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: modelData.available
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colSubtext
                                        }

                                        StyledText {
                                            visible: modelData.battery >= 0
                                            text: "•"
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                        }

                                        MaterialSymbol {
                                            visible: modelData.battery >= 0
                                            text: modelData.charging ? "bolt" : "battery_4_bar"
                                            iconSize: 13
                                            color: root.batteryColor(modelData.battery)
                                        }

                                        StyledText {
                                            visible: modelData.battery >= 0
                                            text: `${modelData.battery}%`
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: root.batteryColor(modelData.battery)
                                        }
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 30
                                    implicitHeight: 30
                                    buttonRadius: 15
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer3
                                    onClicked: root.refresh()
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: KdeConnectService.loading ? "hourglass_top" : "refresh"
                                        iconSize: 16
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }

                            // ── Battery bar ──
                            RowLayout {
                                Layout.fillWidth: true
                                visible: modelData.battery >= 0
                                spacing: 2

                                // Battery body
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 12
                                    radius: 3
                                    color: "transparent"
                                    border.width: 1.5
                                    border.color: root.batteryColor(modelData.battery)

                                    // Fill level
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 2
                                        width: Math.max(0, (parent.width - 4) * Math.max(0, Math.min(100, modelData.battery)) / 100)
                                        radius: 1.5
                                        color: root.batteryColor(modelData.battery)
                                    }

                                    // Charging bolt overlay
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: modelData.charging
                                        text: "bolt"
                                        iconSize: 10
                                        color: Appearance.colors.colOnLayer2
                                    }
                                }

                                // Terminal nub
                                Rectangle {
                                    implicitWidth: 3
                                    implicitHeight: 6
                                    radius: 1
                                    color: root.batteryColor(modelData.battery)
                                }
                            }

                            // ── Media player ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: deviceCard.kdePlayerList.length > 0
                                spacing: 6

                                ListView {
                                    id: playerSourceView
                                    Layout.fillWidth: true
                                    implicitHeight: 148
                                    orientation: ListView.Horizontal
                                    snapMode: ListView.SnapToItem
                                    boundsBehavior: Flickable.StopAtBounds
                                    highlightRangeMode: ListView.StrictlyEnforceRange
                                    preferredHighlightBegin: 0
                                    preferredHighlightEnd: width
                                    clip: true
                                    spacing: 0
                                    model: deviceCard.kdePlayerList

                                    onCurrentIndexChanged: {
                                        if (!deviceCard.currentPlayerResolved)
                                            return
                                        const player = model[currentIndex]
                                        if (typeof player === "string" && player.length > 0)
                                            deviceCard.activatePlayer(player)
                                    }

                                    Connections {
                                        target: deviceCard
                                        function onKdeCurrentPlayerChanged() {
                                            const sourceIndex = deviceCard.kdePlayerList.indexOf(deviceCard.kdeCurrentPlayer)
                                            if (sourceIndex >= 0 && playerSourceView.currentIndex !== sourceIndex)
                                                playerSourceView.currentIndex = sourceIndex
                                        }
                                    }

                                    delegate: Rectangle {
                                        id: playerPage
                                        required property string modelData
                                        required property int index
                                        readonly property bool selected: modelData === deviceCard.kdeCurrentPlayer
                                        readonly property var pagePlayer: deviceCard.playerForSource(modelData)
                                        readonly property real seekStepSeconds: 15
                                        readonly property string artUrl: pagePlayer?.trackArtUrl ?? ""
                                        readonly property string artHash: artUrl.length > 0 ? Qt.md5(artUrl) : ""
                                        readonly property string artPath: artHash.length > 0 ? `${Directories.coverArt}/${artHash}` : ""
                                        property bool artReady: false
                                        readonly property string displayedArt: artReady && artPath.length > 0 ? Qt.resolvedUrl(artPath) : ""
                                        width: playerSourceView.width
                                        height: playerSourceView.height
                                        radius: Appearance.rounding.normal
                                        color: selected
                                            ? Qt.alpha(Appearance.colors.colPrimaryContainer, 0.2)
                                            : Appearance.colors.colLayer3
                                        border.width: 1
                                        border.color: selected
                                            ? Qt.alpha(Appearance.colors.colPrimary, 0.3)
                                            : Appearance.colors.colOutlineVariant

                                        onArtPathChanged: {
                                            if (artPath.length === 0) {
                                                artReady = false;
                                                return;
                                            }
                                            artReady = false;
                                            artDownloader.targetFile = artUrl;
                                            artDownloader.artFilePath = artPath;
                                            artDownloader.running = true;
                                        }

                                        Process {
                                            id: artDownloader
                                            property string targetFile: ""
                                            property string artFilePath: ""
                                            command: ["bash", "-c", `[ -f '${artFilePath}' ] || curl -sSL '${targetFile}' -o '${artFilePath}'`]
                                            onExited: playerPage.artReady = true
                                        }

                                        function seekBy(offsetSeconds) {
                                            if (!(pagePlayer?.canSeek ?? false) || !pagePlayer)
                                                return;
                                            const current = pagePlayer.position ?? 0;
                                            const length = pagePlayer.length ?? 0;
                                            pagePlayer.position = Math.max(0, Math.min(length, current + offsetSeconds));
                                        }

                                        function togglePlayback() {
                                            if (pagePlayer?.canTogglePlaying ?? false) {
                                                if (selected)
                                                    MprisController.setActivePlayer(pagePlayer)
                                                pagePlayer.togglePlaying()
                                                return
                                            }
                                            deviceCard.runPlayerCommand(playerPage.modelData, "playPause")
                                        }

                                        Timer {
                                            running: pagePlayer?.playbackState == MprisPlaybackState.Playing
                                            interval: Config.options.resources.updateInterval
                                            repeat: true
                                            onTriggered: pagePlayer.positionChanged()
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 10

                                            Rectangle {
                                                Layout.preferredWidth: 88
                                                Layout.preferredHeight: 88
                                                radius: Appearance.rounding.small
                                                color: Appearance.colors.colLayer2
                                                clip: true

                                                Image {
                                                    anchors.fill: parent
                                                    source: playerPage.displayedArt
                                                    fillMode: Image.PreserveAspectCrop
                                                    cache: false
                                                    asynchronous: true
                                                }

                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "music_note"
                                                    iconSize: 28
                                                    color: Appearance.colors.colSubtext
                                                    visible: playerPage.displayedArt.length === 0
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                spacing: 4

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: modelData
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    color: selected
                                                        ? Appearance.colors.colPrimary
                                                        : Appearance.colors.colSubtext
                                                    elide: Text.ElideRight
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: StringUtils.cleanMusicTitle(pagePlayer?.trackTitle) || modelData
                                                    font.pixelSize: Appearance.font.pixelSize.normal
                                                    font.weight: Font.Medium
                                                    color: Appearance.colors.colOnLayer2
                                                    elide: Text.ElideRight
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: pagePlayer?.trackArtist || (selected
                                                        ? Translation.tr("Current source")
                                                        : Translation.tr("Available source"))
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    color: Appearance.colors.colSubtext
                                                    elide: Text.ElideRight
                                                }

                                                Item { Layout.fillHeight: true }

                                                Item {
                                                    Layout.fillWidth: true
                                                    implicitHeight: trackTime.implicitHeight + sliderRow.implicitHeight + 2

                                                    StyledText {
                                                        id: trackTime
                                                        anchors.bottom: sliderRow.top
                                                        anchors.bottomMargin: 5
                                                        anchors.left: parent.left
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        color: Appearance.colors.colSubtext
                                                        elide: Text.ElideRight
                                                        text: pagePlayer
                                                            ? `${StringUtils.friendlyTimeForSeconds(pagePlayer?.position)} / ${StringUtils.friendlyTimeForSeconds(pagePlayer?.length)}`
                                                            : Translation.tr("Swipe or tap controls")
                                                    }

                                                    RowLayout {
                                                        id: sliderRow
                                                        anchors {
                                                            left: parent.left
                                                            right: parent.right
                                                            bottom: parent.bottom
                                                        }
                                                        spacing: 6

                                                        RippleButton {
                                                            implicitWidth: 24
                                                            implicitHeight: 24
                                                            enabled: deviceCard.deviceAvailable
                                                            buttonRadius: implicitHeight / 2
                                                            colBackground: "transparent"
                                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                                            onClicked: {
                                                                if (pagePlayer?.canGoPrevious ?? false) {
                                                                    if (selected)
                                                                        MprisController.setActivePlayer(pagePlayer)
                                                                    pagePlayer.previous()
                                                                } else {
                                                                    deviceCard.runPlayerCommand(playerPage.modelData, "previous")
                                                                }
                                                            }

                                                            contentItem: MaterialSymbol {
                                                                anchors.centerIn: parent
                                                                text: "skip_previous"
                                                                iconSize: Appearance.font.pixelSize.large
                                                                color: Appearance.colors.colOnLayer2
                                                            }
                                                        }

                                                        RippleButton {
                                                            implicitWidth: 32
                                                            implicitHeight: 28
                                                            visible: pagePlayer?.canSeek ?? false
                                                            enabled: deviceCard.deviceAvailable
                                                            buttonRadius: implicitHeight / 2
                                                            colBackground: Appearance.colors.colLayer2
                                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                                            onClicked: {
                                                                if (pagePlayer?.canSeek ?? false)
                                                                    playerPage.seekBy(-playerPage.seekStepSeconds)
                                                                else
                                                                    deviceCard.runPlayerCommand(playerPage.modelData, "seek", ["-15000"])
                                                            }

                                                            contentItem: StyledText {
                                                                anchors.centerIn: parent
                                                                text: "-15"
                                                                font.pixelSize: Appearance.font.pixelSize.small
                                                                color: Appearance.colors.colOnLayer2
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                            }
                                                        }

                                                        Item {
                                                            Layout.fillWidth: true
                                                            implicitHeight: Math.max(seekSlider.implicitHeight, progressBar.implicitHeight)

                                                            StyledSlider {
                                                                id: seekSlider
                                                                anchors.fill: parent
                                                                visible: pagePlayer?.canSeek ?? false
                                                                enabled: visible
                                                                configuration: StyledSlider.Configuration.Wavy
                                                                highlightColor: Appearance.colors.colPrimary
                                                                trackColor: Appearance.colors.colSecondaryContainer
                                                                handleColor: Appearance.colors.colPrimary
                                                                value: {
                                                                    const length = pagePlayer?.length ?? 0;
                                                                    return length > 0 ? (pagePlayer?.position ?? 0) / length : 0;
                                                                }
                                                                onMoved: {
                                                                    if (pagePlayer?.canSeek ?? false) {
                                                                        const length = pagePlayer?.length ?? 0;
                                                                        if (length > 0)
                                                                            pagePlayer.position = value * length;
                                                                    }
                                                                }
                                                            }

                                                            StyledProgressBar {
                                                                id: progressBar
                                                                anchors {
                                                                    left: parent.left
                                                                    right: parent.right
                                                                    verticalCenter: parent.verticalCenter
                                                                }
                                                                visible: !(pagePlayer?.canSeek ?? false)
                                                                wavy: pagePlayer?.isPlaying ?? false
                                                                highlightColor: Appearance.colors.colPrimary
                                                                trackColor: Appearance.colors.colSecondaryContainer
                                                                value: {
                                                                    const length = pagePlayer?.length ?? 0;
                                                                    return length > 0 ? (pagePlayer?.position ?? 0) / length : 0;
                                                                }
                                                            }
                                                        }

                                                        RippleButton {
                                                            implicitWidth: 32
                                                            implicitHeight: 28
                                                            visible: pagePlayer?.canSeek ?? false
                                                            enabled: deviceCard.deviceAvailable
                                                            buttonRadius: implicitHeight / 2
                                                            colBackground: Appearance.colors.colLayer2
                                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                                            onClicked: {
                                                                if (pagePlayer?.canSeek ?? false)
                                                                    playerPage.seekBy(playerPage.seekStepSeconds)
                                                                else
                                                                    deviceCard.runPlayerCommand(playerPage.modelData, "seek", ["15000"])
                                                            }

                                                            contentItem: StyledText {
                                                                anchors.centerIn: parent
                                                                text: "+15"
                                                                font.pixelSize: Appearance.font.pixelSize.small
                                                                color: Appearance.colors.colOnLayer2
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                            }
                                                        }

                                                        RippleButton {
                                                            implicitWidth: 24
                                                            implicitHeight: 24
                                                            enabled: deviceCard.deviceAvailable
                                                            buttonRadius: implicitHeight / 2
                                                            colBackground: "transparent"
                                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                                            onClicked: {
                                                                if (pagePlayer?.canGoNext ?? false) {
                                                                    if (selected)
                                                                        MprisController.setActivePlayer(pagePlayer)
                                                                    pagePlayer.next()
                                                                } else {
                                                                    deviceCard.runPlayerCommand(playerPage.modelData, "next")
                                                                }
                                                            }

                                                            contentItem: MaterialSymbol {
                                                                anchors.centerIn: parent
                                                                text: "skip_next"
                                                                iconSize: Appearance.font.pixelSize.large
                                                                color: Appearance.colors.colOnLayer2
                                                            }
                                                        }
                                                    }

                                                    RippleButton {
                                                        id: playPauseButton
                                                        anchors.right: parent.right
                                                        anchors.bottom: sliderRow.top
                                                        anchors.bottomMargin: 5
                                                        implicitWidth: 42
                                                        implicitHeight: 42
                                                        buttonRadius: pagePlayer?.isPlaying ? Appearance.rounding.normal : implicitHeight / 2
                                                        colBackground: pagePlayer?.isPlaying
                                                            ? Appearance.colors.colPrimary
                                                            : Appearance.colors.colPrimaryContainer
                                                        colBackgroundHover: pagePlayer?.isPlaying
                                                            ? Appearance.colors.colPrimaryHover
                                                            : Qt.tint(Appearance.colors.colPrimaryContainer, "#18ffffff")
                                                        onClicked: playerPage.togglePlayback()

                                                        contentItem: MaterialSymbol {
                                                            anchors.centerIn: parent
                                                            text: pagePlayer?.isPlaying ? "pause" : "play_arrow"
                                                            iconSize: 22
                                                            color: pagePlayer?.isPlaying
                                                                ? Appearance.colors.colOnPrimary
                                                                : Appearance.colors.colOnPrimaryContainer
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: deviceCard.kdePlayerList.length > 1
                                    spacing: 6

                                    Repeater {
                                        model: deviceCard.kdePlayerList.length

                                        delegate: Rectangle {
                                            required property int index
                                            readonly property bool activeDot: index === playerSourceView.currentIndex
                                            implicitWidth: activeDot ? 14 : 8
                                            implicitHeight: 8
                                            radius: 4
                                            color: activeDot
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colOutlineVariant

                                            Behavior on implicitWidth {
                                                NumberAnimation { duration: 120 }
                                            }

                                            Behavior on color {
                                                ColorAnimation { duration: 120 }
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    MaterialSymbol {
                                        text: "volume_mute"
                                        iconSize: 14
                                        color: Appearance.colors.colSubtext
                                    }

                                    StyledSlider {
                                        id: volumeSlider
                                        Layout.fillWidth: true
                                        from: 0; to: 100
                                        readonly property var activePagePlayer: deviceCard.playerForSource(deviceCard.kdeCurrentPlayer)
                                        value: pressed ? value : Math.round((activePagePlayer?.volume ?? 0.8) * 100)
                                        onMoved: {
                                            if (playerSourceView.currentIndex >= 0 && playerSourceView.currentIndex < deviceCard.kdePlayerList.length)
                                                deviceCard.activatePlayer(deviceCard.kdePlayerList[playerSourceView.currentIndex])
                                            if (activePagePlayer)
                                                activePagePlayer.volume = value / 100
                                            else
                                                Quickshell.execDetached(["qdbus", "org.kde.kdeconnect",
                                                    `/modules/kdeconnect/devices/${deviceCard.deviceId}/mprisremote`,
                                                    "org.kde.kdeconnect.device.mprisremote.volume",
                                                    Math.round(value).toString()])
                                        }
                                    }

                                    MaterialSymbol {
                                        text: "volume_up"
                                        iconSize: 14
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                            }

                            // ── Send file ──
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 36
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer3

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 4
                                    anchors.topMargin: 4
                                    anchors.bottomMargin: 4
                                    spacing: 4

                                    MaterialSymbol {
                                        text: "attach_file"
                                        iconSize: 15
                                        color: Appearance.colors.colSubtext
                                    }

                                    TextField {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        text: root.sharePath
                                        onTextChanged: root.sharePath = text
                                        placeholderText: Translation.tr("File path…")
                                        color: Appearance.colors.colOnLayer3
                                        placeholderTextColor: Appearance.colors.colSubtext
                                        verticalAlignment: TextInput.AlignVCenter
                                        leftPadding: 4; rightPadding: 4
                                        topPadding: 0; bottomPadding: 0
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        background: Item {}
                                    }

                                    RippleButton {
                                        implicitWidth: 26; implicitHeight: 26
                                        buttonRadius: 13
                                        colBackground: Appearance.colors.colLayer2
                                        colBackgroundHover: Appearance.colors.colLayer2Hover
                                        onClicked: { filePickerProc.running = false; filePickerProc.running = true; }
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "folder_open"; iconSize: 14
                                            color: Appearance.colors.colOnLayer2
                                        }
                                    }

                                    RippleButton {
                                        implicitWidth: 26; implicitHeight: 26
                                        buttonRadius: 13
                                        enabled: deviceCard.deviceAvailable && root.sharePath.trim().length > 0
                                        colBackground: Appearance.colors.colPrimary
                                        colBackgroundHover: Qt.tint(Appearance.colors.colPrimary, "#18ffffff")
                                        onClicked: root.sendFile(deviceCard.deviceId, root.sharePath)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "send"; iconSize: 14
                                            color: Appearance.colors.colOnPrimary
                                        }
                                    }
                                }
                            }

                            // ── Mini action strip ──
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [
                                        { icon: "notifications_active", tip: "Ping",      args: ["--device", modelData.id, "--ping", "--ping-msg", "Ping from Quickshell"] },
                                        { icon: "ring_volume",          tip: "Ring",      args: ["--device", modelData.id, "--ring"] },
                                        { icon: "content_paste",        tip: Translation.tr("Clipboard"), args: ["--device", modelData.id, "--send-clipboard"] },
                                        { icon: "lock",                 tip: Translation.tr("Lock"),      args: ["--device", modelData.id, "--lock"] },
                                        { icon: "lock_open",            tip: "Unlock",    args: ["--device", modelData.id, "--unlock"] },
                                        { icon: "hard_drive",           tip: "Mount",     args: ["--device", modelData.id, "--mount"] },
                                        { icon: "folder",               tip: "Storage",   openPath: true }
                                    ]
                                    delegate: RippleButton {
                                        required property var modelData
                                        implicitWidth: 32; implicitHeight: 32
                                        buttonRadius: 16
                                        enabled: deviceCard.deviceAvailable
                                        colBackground: Appearance.colors.colLayer3
                                        colBackgroundHover: Appearance.colors.colLayer3Hover
                                        onClicked: {
                                            if (modelData.openPath) {
                                                root.openStorageOrMount(deviceCard.deviceId, deviceCard.modelData.mountPoint ?? "");
                                            } else {
                                                root.runAction(modelData.args);
                                            }
                                        }
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: modelData.icon; iconSize: 15
                                            color: Appearance.colors.colOnLayer3
                                        }
                                        StyledToolTip { text: modelData.tip }
                                    }
                                }
                            }

                            // ── Send text ──
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer3

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 4
                                    anchors.topMargin: 3
                                    anchors.bottomMargin: 3
                                    spacing: 4

                                    TextField {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        placeholderText: Translation.tr("Send text…")
                                        text: deviceCard.keyPayload
                                        onTextChanged: deviceCard.keyPayload = text
                                        color: Appearance.colors.colOnLayer3
                                        placeholderTextColor: Appearance.colors.colSubtext
                                        verticalAlignment: TextInput.AlignVCenter
                                        leftPadding: 0; rightPadding: 0
                                        topPadding: 0; bottomPadding: 0
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        background: Item {}
                                    }

                                    RippleButton {
                                        implicitWidth: 24; implicitHeight: 24
                                        buttonRadius: 12
                                        enabled: deviceCard.deviceAvailable && deviceCard.keyPayload.trim().length > 0
                                        colBackground: Appearance.colors.colPrimary
                                        colBackgroundHover: Qt.tint(Appearance.colors.colPrimary, "#18ffffff")
                                        onClicked: root.runAction(["--device", deviceCard.deviceId, "--share-text", deviceCard.keyPayload.trim()])
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "send"; iconSize: 13
                                            color: Appearance.colors.colOnPrimary
                                        }
                                    }
                                }
                            }

                            // ── Remote commands (if any) ──
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: (modelData.remoteCommands ?? []).length > 0

                                Repeater {
                                    model: modelData.remoteCommands ?? []
                                    delegate: RippleButton {
                                        required property var modelData
                                        implicitHeight: 28
                                        implicitWidth: cmdLabel.implicitWidth + 28
                                        buttonRadius: 14
                                        enabled: deviceCard.deviceAvailable
                                        colBackground: Appearance.colors.colLayer3
                                        colBackgroundHover: Appearance.colors.colLayer3Hover
                                        onClicked: root.runAction(["--device", deviceCard.deviceId, "--execute-command", modelData.id])
                                        contentItem: RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 4
                                            MaterialSymbol { text: "flash_on"; iconSize: 12; color: Appearance.colors.colOnLayer3 }
                                            StyledText {
                                                id: cmdLabel
                                                text: modelData.name
                                                font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                                color: Appearance.colors.colOnLayer3
                                            }
                                        }
                                    }
                                }
                            }

                            // ── SMS ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: modelData.available

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    MaterialSymbol {
                                        text: "sms"
                                        iconSize: 14
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Messages")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer2
                                    }

                                    StyledText {
                                        text: `${(modelData.smsConversations ?? []).length}`
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                StyledFlickable {
                                    Layout.fillWidth: true
                                    implicitHeight: Math.min(contentHeight, 260)
                                    contentHeight: smsRepeaterColumn.implicitHeight
                                    clip: true

                                    ColumnLayout {
                                        id: smsRepeaterColumn
                                        width: parent.width
                                        spacing: 6

                                        Repeater {
                                            model: modelData.smsConversations ?? []
                                            delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        id: smsItem
                                        property bool expanded: false
                                        property string replyText: ""
                                        Layout.fillWidth: true
                                        radius: Appearance.rounding.normal
                                        color: Appearance.colors.colLayer3
                                        implicitHeight: smsInner.implicitHeight + 20
                                        clip: true

                                        Behavior on implicitHeight {
                                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                        }

                                        ColumnLayout {
                                            id: smsInner
                                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                                            spacing: 4

                                            // ── Header ──
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: smsItem.modelData.contact || Translation.tr("Unknown")
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: Font.Medium
                                                    color: smsItem.modelData.read ? Appearance.colors.colOnLayer3 : Appearance.colors.colPrimary
                                                    elide: Text.ElideRight
                                                }

                                                StyledText {
                                                    text: {
                                                        const ms = smsItem.modelData.timestamp || 0;
                                                        if (!ms) return "";
                                                        const d = new Date(ms);
                                                        const now = new Date();
                                                        const diffDays = Math.floor((now - d) / 86400000);
                                                        if (diffDays === 0) return d.toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'});
                                                        if (diffDays < 7) return d.toLocaleDateString([], {weekday:'short'});
                                                        return d.toLocaleDateString([], {month:'short', day:'numeric'});
                                                    }
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    color: Appearance.colors.colSubtext
                                                }

                                                NotificationGroupExpandButton {
                                                    count: 1
                                                    expanded: smsItem.expanded
                                                    onClicked: smsItem.expanded = !smsItem.expanded
                                                }
                                            }

                                            // ── Preview (collapsed) ──
                                            StyledText {
                                                Layout.fillWidth: true
                                                visible: !smsItem.expanded
                                                text: (smsItem.modelData.sent ? "↗ " : "") + (smsItem.modelData.body || "")
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colSubtext
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                                wrapMode: Text.NoWrap
                                            }

                                            // ── Full body + reply (expanded) ──
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                visible: smsItem.expanded
                                                spacing: 8

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: smsItem.modelData.body || ""
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    color: Appearance.colors.colOnLayer3
                                                    wrapMode: Text.Wrap
                                                    textFormat: Text.PlainText
                                                }

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 4

                                                    TextField {
                                                        Layout.fillWidth: true
                                                        implicitHeight: 28
                                                        placeholderText: Translation.tr("Reply…")
                                                        text: smsItem.replyText
                                                        onTextChanged: smsItem.replyText = text
                                                        color: Appearance.colors.colOnLayer3
                                                        placeholderTextColor: Appearance.colors.colSubtext
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        leftPadding: 6; rightPadding: 6
                                                        topPadding: 0; bottomPadding: 0
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        background: Rectangle {
                                                            color: Appearance.colors.colLayer2
                                                            radius: Appearance.rounding.small
                                                        }
                                                        Keys.onReturnPressed: {
                                                            if (smsItem.replyText.trim().length > 0)
                                                                sendReplyBtn.clicked()
                                                        }
                                                    }

                                                    RippleButton {
                                                        id: sendReplyBtn
                                                        implicitWidth: 28; implicitHeight: 28
                                                        buttonRadius: 14
                                                        enabled: deviceCard.deviceAvailable && smsItem.replyText.trim().length > 0
                                                        colBackground: Appearance.colors.colPrimary
                                                        colBackgroundHover: Qt.tint(Appearance.colors.colPrimary, "#18ffffff")
                                                        onClicked: {
                                                            const addr = smsItem.modelData.contact || "";
                                                            if (addr.length > 0 && smsItem.replyText.trim().length > 0) {
                                                                root.runAction(["--device", deviceCard.deviceId,
                                                                    "--send-sms", smsItem.replyText.trim(),
                                                                    "--destination", addr]);
                                                                smsItem.replyText = "";
                                                            }
                                                        }
                                                        contentItem: MaterialSymbol {
                                                            anchors.centerIn: parent
                                                            text: "send"; iconSize: 14
                                                            color: Appearance.colors.colOnPrimary
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: !smsItem.expanded
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: smsItem.expanded = true
                                        }
                                    } // Rectangle delegate
                                        } // Repeater
                                    } // smsRepeaterColumn ColumnLayout
                                } // StyledFlickable
                            } // SMS section ColumnLayout

                            // ── Notifications ──
                            ColumnLayout {
                                id: notifSection
                                Layout.fillWidth: true
                                spacing: 6

                                property var rawNotifs: modelData.notifications ?? []
                                property var rawByApp: {
                                    const groups = {}
                                    for (const n of rawNotifs) {
                                        const app = (n.appName ?? "").length > 0 ? n.appName : (n.ticker ?? "").split(":")[0].trim() || Translation.tr("Unknown")
                                        if (!groups[app]) groups[app] = { appName: app, iconPath: n.iconPath ?? "", notifs: [] }
                                        groups[app].notifs.push(n)
                                    }
                                    return groups
                                }
                                property var rawAppNames: Object.keys(rawByApp).sort()

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    MaterialSymbol {
                                        text: "notifications"
                                        iconSize: 14
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Notifications")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer2
                                    }

                                    StyledText {
                                        text: `${notifSection.rawNotifs.length}`
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                Repeater {
                                    model: notifSection.rawAppNames
                                    delegate: ColumnLayout {
                                        required property string modelData
                                        id: appGroup
                                        property var group: notifSection.rawByApp[modelData] ?? { appName: "", iconPath: "", notifs: [] }
                                        Layout.fillWidth: true
                                        spacing: 3

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 5

                                            StyledImage {
                                                visible: appGroup.group.iconPath.length > 0
                                                source: appGroup.group.iconPath.length > 0 ? `file://${appGroup.group.iconPath}` : ""
                                                width: 14
                                                height: 14
                                                fillMode: Image.PreserveAspectFit
                                                sourceSize.width: 14
                                                sourceSize.height: 14
                                            }
                                            MaterialSymbol {
                                                visible: appGroup.group.iconPath.length === 0
                                                text: "apps"
                                                iconSize: 13
                                                color: Appearance.colors.colSubtext
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: appGroup.group.appName
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                font.weight: Font.Medium
                                                color: Appearance.colors.colOnLayer2
                                                elide: Text.ElideRight
                                            }

                                            StyledText {
                                                text: `${appGroup.group.notifs.length}`
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colSubtext
                                            }
                                        }

                                        Repeater {
                                            model: appGroup.group.notifs.length
                                            delegate: Rectangle {
                                                required property int index
                                                property var notif: appGroup.group.notifs[index]
                                                property bool expanded: false
                                                Layout.fillWidth: true
                                                radius: Appearance.rounding.small
                                                color: Appearance.colors.colLayer3
                                                clip: true
                                                implicitHeight: notifItemCol.implicitHeight + 12

                                                Behavior on implicitHeight {
                                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: parent.expanded = !parent.expanded
                                                }

                                                ColumnLayout {
                                                    id: notifItemCol
                                                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 8; rightMargin: 8; topMargin: 6 }
                                                    spacing: 2

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 4

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            visible: (notif.title ?? "").length > 0
                                                            text: notif.title ?? ""
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            font.weight: Font.Medium
                                                            color: Appearance.colors.colOnLayer3
                                                            elide: Text.ElideRight
                                                        }

                                                        MaterialSymbol {
                                                            visible: (notif.text ?? (notif.ticker ?? "")).length > 0
                                                            text: "expand_more"
                                                            iconSize: 13
                                                            color: Appearance.colors.colSubtext
                                                            rotation: expanded ? 180 : 0
                                                            Behavior on rotation {
                                                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                                            }
                                                        }
                                                    }

                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        visible: expanded && (notif.text ?? (notif.ticker ?? "")).length > 0
                                                        text: notif.text || notif.ticker || ""
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        color: Appearance.colors.colSubtext
                                                        wrapMode: Text.Wrap
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                StyledText {
                                    visible: notifSection.rawNotifs.length === 0
                                    Layout.fillWidth: true
                                    text: Translation.tr("No notifications")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }

                StyledText {
                    visible: root.devices.length === 0 && root.lastError.length === 0
                    text: Translation.tr("No paired devices detected.")
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
            }
        }
    }
}
