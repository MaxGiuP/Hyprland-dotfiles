pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item { // Player instance
    id: root
    required property MprisPlayer player
    property var artUrl: player?.trackArtUrl ?? ""
    property string artDownloadLocation: Directories.coverArt
    // Namespace KDE Connect art cache so it never shares a cached file with desktop players,
    // even when both report the same artUrl for the same track.
    property string artFileName: Qt.md5((isKdeConnectSource ? "kdeconnect:" : "") + (artUrl ?? ""))
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property color artDominantColor: ColorUtils.mix((colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary), Appearance.colors.colPrimaryContainer, 0.8) || Appearance.m3colors.m3secondaryContainer
    property bool downloaded: false
    property list<real> visualizerPoints: []
    property real maxVisualizerValue: 1000 // Max value in the data points
    property int visualizerSmoothing: 2 // Number of points to average for smoothing
    property real radius
    property real maxArtPreviewSize: 120
    // KDE Connect players get a source badge in the art corner.
    readonly property bool isKdeConnectSource: (player?.dbusName ?? "").toLowerCase().includes("kdeconnect")
    readonly property string sourceIcon: isKdeConnectSource ? "phone_android" : "laptop_chromebook"
    readonly property real seekStepSeconds: 15
    readonly property string desktopEntryId: player?.desktopEntry ?? ""
    readonly property var desktopEntry: DesktopEntries.byId(desktopEntryId) ?? DesktopEntries.heuristicLookup(desktopEntryId)
    readonly property string fallbackIconName: {
        const candidates = [
            desktopEntry?.icon ?? "",
            desktopEntryId,
            player?.identity ?? "",
            player?.dbusName ?? "",
            (player?.dbusName ?? "").replace(/^org\.mpris\.MediaPlayer2\./, "")
        ];

        for (const candidate of candidates) {
            const guessed = AppSearch.guessIcon(candidate);
            if (guessed && guessed !== "image-missing")
                return guessed;
        }

        return "";
    }
    readonly property string fallbackArtPath: fallbackIconName.length > 0
        ? Quickshell.iconPath(fallbackIconName, "image-missing")
        : ""
    readonly property string preferredPlayerThumbnail: fallbackArtPath.length > 0 ? fallbackArtPath : ""
    readonly property bool matchesActiveTrack: {
        if (!root.player || !MprisController.activePlayer)
            return false;
        if (root.player.uniqueId === MprisController.activePlayer.uniqueId)
            return true;

        const thisTitle = `${root.player?.trackTitle ?? ""}`.trim();
        const activeTitle = `${MprisController.activePlayer?.trackTitle ?? ""}`.trim();
        const thisArtist = `${root.player?.trackArtist ?? ""}`.trim();
        const activeArtist = `${MprisController.activePlayer?.trackArtist ?? ""}`.trim();
        const thisArt = `${root.player?.trackArtUrl ?? ""}`.trim();
        const activeArt = `${MprisController.activePlayer?.trackArtUrl ?? ""}`.trim();

        if (thisArt.length > 0 && activeArt.length > 0 && thisArt === activeArt)
            return true;
        if (thisTitle.length > 0 && thisTitle === activeTitle && thisArtist === activeArtist)
            return true;
        if (thisTitle.length > 0 && thisTitle === activeTitle && (thisArtist.length === 0 || activeArtist.length === 0))
            return true;
        return false;
    }
    property string displayedArtFilePath: {
        // Only reuse the bar's cached art for the exact active player, not for players that
        // merely match by title/art (which caused KDE Connect to show desktop art).
        if (root.player?.uniqueId === MprisController.activePlayer?.uniqueId && MprisController.activeArtPath.length > 0)
            return MprisController.activeArtPath;
        if (root.downloaded)
            return Qt.resolvedUrl(artFilePath);
        return preferredPlayerThumbnail;
    }

    function seekBy(offsetSeconds) {
        if (!(root.player?.canSeek ?? false) || !root.player)
            return;

        const current = root.player.position ?? 0;
        const length = root.player.length ?? 0;
        root.player.position = Math.max(0, Math.min(length, current + offsetSeconds));
    }

    component TrackChangeButton: RippleButton {
        implicitWidth: 24
        implicitHeight: 24

        property var iconName
        colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 1)
        colBackgroundHover: blendedColors.colSecondaryContainerHover
        colRipple: blendedColors.colSecondaryContainerActive

        contentItem: MaterialSymbol {
            iconSize: Appearance.font.pixelSize.huge
            fill: 1
            horizontalAlignment: Text.AlignHCenter
            color: blendedColors.colOnSecondaryContainer
            text: iconName

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    Timer { // Force update for revision
        running: root.player?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: {
            root.player.positionChanged()
        }
    }

    function resetArtworkState() {
        coverArtDownloader.running = false
        root.downloaded = false
    }

    onArtUrlChanged: resetArtworkState()
    onArtFilePathChanged: {
        if ((root.artUrl ?? "").length === 0) {
            resetArtworkState()
            return;
        }

        coverArtDownloader.targetFile = root.artUrl
        coverArtDownloader.artFilePath = root.artFilePath
        root.downloaded = false
        coverArtDownloader.running = true
    }

    Component.onCompleted: {
        if ((root.artUrl ?? "").length > 0) {
            coverArtDownloader.targetFile = root.artUrl
            coverArtDownloader.artFilePath = root.artFilePath
            root.downloaded = false
            coverArtDownloader.running = true
        }
    }

    Process { // Cover art downloader
        id: coverArtDownloader
        property string targetFile: root.artUrl ?? ""
        property string artFilePath: root.artFilePath
        command: [ "bash", "-c", `[ -f '${artFilePath}' ] || curl -sSL '${targetFile}' -o '${artFilePath}'` ]
        onExited: () => {
            root.downloaded = true
        }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0 // 2^0 = 1 color
        rescaleSize: 1 // Rescale to 1x1 pixel for faster processing
    }

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: artDominantColor
    }

    StyledRectangularShadow {
        target: background
    }
    Rectangle { // Background
        id: background
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        color: ColorUtils.applyAlpha(blendedColors.colLayer0, 1)
        radius: root.radius

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: background.width
                height: background.height
                radius: background.radius
            }
        }

        Image {
            id: blurredArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            sourceSize.width: background.width
            sourceSize.height: background.height
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true

            layer.enabled: true
            layer.effect: StyledBlurEffect {
                source: blurredArt
            }

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(blendedColors.colLayer0, 0.3)
                radius: root.radius
            }
        }

        WaveVisualizer {
            id: visualizerCanvas
            anchors.fill: parent
            live: root.player?.isPlaying
            points: root.visualizerPoints
            maxVisualizerValue: root.maxVisualizerValue
            smoothing: root.visualizerSmoothing
            color: blendedColors.colPrimary
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 13
            spacing: 15

            Rectangle { // Art background
                id: artBackground
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: true
                Layout.maximumHeight: root.maxArtPreviewSize
                Layout.preferredWidth: Math.min(height, root.maxArtPreviewSize)
                Layout.maximumWidth: root.maxArtPreviewSize
                implicitWidth: root.maxArtPreviewSize
                radius: Appearance.rounding.verysmall
                color: ColorUtils.transparentize(blendedColors.colLayer1, 0.5)

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: artBackground.width
                        height: artBackground.height
                        radius: artBackground.radius
                    }
                }

                StyledImage { // Art image
                    id: mediaArt
                    property int size: parent.height
                    anchors.fill: parent

                    source: root.displayedArtFilePath
                    fillMode: Image.PreserveAspectCrop
                    cache: true
                    antialiasing: true

                    width: size
                    height: size
                    sourceSize.width: size
                    sourceSize.height: size
                }

                Rectangle {
                    visible: root.isKdeConnectSource
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 6
                    implicitWidth: 22
                    implicitHeight: 18
                    radius: 9
                    color: ColorUtils.transparentize(blendedColors.colLayer0, 0.22)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: Appearance.font.pixelSize.tiny
                        fill: 1
                        color: blendedColors.colOnLayer0
                        text: root.sourceIcon
                    }
                }
            }

            ColumnLayout { // Info & controls
                Layout.fillHeight: true
                spacing: 2

                StyledText {
                    id: trackTitle
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: blendedColors.colOnLayer0
                    elide: Text.ElideRight
                    text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || Translation.tr("Nothing playing")
                    animateChange: true
                    animationDistanceX: 6
                    animationDistanceY: 0
                }
                StyledText {
                    id: trackArtist
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: blendedColors.colSubtext
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.player?.trackArtist
                    animateChange: true
                    animationDistanceX: 6
                    animationDistanceY: 0
                }
                Item { Layout.fillHeight: true }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: trackTime.implicitHeight + sliderRow.implicitHeight

                    StyledText {
                        id: trackTime
                        anchors.bottom: sliderRow.top
                        anchors.bottomMargin: 5
                        anchors.left: parent.left
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: blendedColors.colSubtext
                        elide: Text.ElideRight
                        text: `${StringUtils.friendlyTimeForSeconds(root.player?.position)} / ${StringUtils.friendlyTimeForSeconds(root.player?.length)}`
                    }
                    RowLayout {
                        id: sliderRow
                        anchors {
                            bottom: parent.bottom
                            left: parent.left
                            right: parent.right
                        }
                        TrackChangeButton {
                            iconName: "skip_previous"
                            downAction: () => root.player?.previous()
                        }
                        TrackChangeButton {
                            implicitWidth: 32
                            implicitHeight: 28
                            visible: root.player?.canSeek ?? false
                            downAction: () => root.seekBy(-root.seekStepSeconds)

                            contentItem: StyledText {
                                text: "-15"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: blendedColors.colOnSecondaryContainer
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        Item {
                            id: progressBarContainer
                            Layout.fillWidth: true
                            implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)

                            Loader {
                                id: sliderLoader
                                anchors.fill: parent
                                active: root.player?.canSeek ?? false
                                sourceComponent: StyledSlider { 
                                    configuration: StyledSlider.Configuration.Wavy
                                    highlightColor: blendedColors.colPrimary
                                    trackColor: blendedColors.colSecondaryContainer
                                    handleColor: blendedColors.colPrimary
                                    value: root.player?.position / root.player?.length
                                    onMoved: {
                                        root.player.position = value * root.player.length;
                                    }
                                }
                            }

                            Loader {
                                id: progressBarLoader
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: parent.left
                                    right: parent.right
                                }
                                active: !(root.player?.canSeek ?? false)
                                sourceComponent: StyledProgressBar { 
                                    wavy: root.player?.isPlaying
                                    highlightColor: blendedColors.colPrimary
                                    trackColor: blendedColors.colSecondaryContainer
                                    value: root.player?.position / root.player?.length
                                }
                            }

                            
                        }
                        TrackChangeButton {
                            implicitWidth: 32
                            implicitHeight: 28
                            visible: root.player?.canSeek ?? false
                            downAction: () => root.seekBy(root.seekStepSeconds)

                            contentItem: StyledText {
                                text: "+15"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: blendedColors.colOnSecondaryContainer
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        TrackChangeButton {
                            iconName: "skip_next"
                            downAction: () => root.player?.next()
                        }
                    }

                    RippleButton {
                        id: playPauseButton
                        anchors.right: parent.right
                        anchors.bottom: sliderRow.top
                        anchors.bottomMargin: 5
                        property real size: 44
                        implicitWidth: size
                        implicitHeight: size
                        downAction: () => root.player.togglePlaying();

                        buttonRadius: root.player?.isPlaying ? Appearance?.rounding.normal : size / 2
                        colBackground: root.player?.isPlaying ? blendedColors.colPrimary : blendedColors.colSecondaryContainer
                        colBackgroundHover: root.player?.isPlaying ? blendedColors.colPrimaryHover : blendedColors.colSecondaryContainerHover
                        colRipple: root.player?.isPlaying ? blendedColors.colPrimaryActive : blendedColors.colSecondaryContainerActive

                        contentItem: MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.huge
                            fill: 1
                            horizontalAlignment: Text.AlignHCenter
                            color: root.player?.isPlaying ? blendedColors.colOnPrimary : blendedColors.colOnSecondaryContainer
                            text: root.player?.isPlaying ? "pause" : "play_arrow"

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }
            }
        }
    }
}
