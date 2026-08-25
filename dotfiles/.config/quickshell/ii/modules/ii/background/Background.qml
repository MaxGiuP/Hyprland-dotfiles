pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather

Variants {
    id: root
    model: Quickshell.screens

    Scope {
        id: screenScope
        required property var modelData

        PanelWindow {
            id: bgRoot

        // Hide when fullscreen
        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(screenScope.modelData)
        readonly property var monitorData: HyprlandData.monitors.find(m => m.name === monitor?.name)
        readonly property string visibleSpecialWorkspace: `${monitorData?.specialWorkspace?.name ?? ""}`
        readonly property string activeWorkspaceName: `${monitorData?.activeWorkspace?.name ?? ""}`
        readonly property bool showingTvWorkspace: visibleSpecialWorkspace === "special:tv" || (monitor?.name === "HDMI-A-2" && activeWorkspaceName === "21")
        readonly property bool showingTvAppWorkspace: visibleSpecialWorkspace === "special:tv-app"
        readonly property bool showingTvModeWorkspace: showingTvWorkspace || showingTvAppWorkspace
        readonly property bool fullscreenOnMonitor: HyprlandData.activeWorkspaceHasFullscreenForMonitor(monitor?.name)
        visible: GlobalStates.screenLocked || showingTvModeWorkspace || !fullscreenOnMonitor || !Config?.options.background.hideWhenFullscreen
        property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
        property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
        property int lastWorkspaceId: relevantWindows[relevantWindows.length - 1]?.workspace.id || 10
        // Wallpaper
        property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
        property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
        property bool wallpaperAnimationArmed: false
        property string displayedWallpaperPath: wallpaperPath
        property string revealWallpaperPath: ""
        property string queuedRevealWallpaperPath: ""
        property bool wallpaperRevealActive: false
        property bool wallpaperRevealPending: false
        property bool wallpaperRevealWarming: false
        property int wallpaperRevealWarmupFrames: 0
        property bool wallpaperPreloadWarming: false
        property int wallpaperPreloadWarmupFrames: 0
        property real wallpaperRevealProgress: 1
        readonly property real wallpaperRevealOriginX: screenWidth
        readonly property real wallpaperRevealOriginY: 0
        readonly property real wallpaperRevealEdge: Math.max(48, Math.min(screenWidth, screenHeight) * 0.075)
        readonly property real wallpaperRevealMaxRadius: Math.sqrt(screenWidth * screenWidth + screenHeight * screenHeight) + wallpaperRevealEdge * 5
        readonly property real wallpaperRevealRadius: wallpaperRevealMaxRadius * wallpaperRevealProgress
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        readonly property real monitorScale: monitor?.scale ?? 1
        readonly property real screenWidth: Math.max(1, width || screen?.width || screenScope.modelData.width || 1)
        readonly property real screenHeight: Math.max(1, height || screen?.height || screenScope.modelData.height || 1)
        property real wallpaperToScreenRatio: Math.min(wallpaperWidth / screenWidth, wallpaperHeight / screenHeight)
        property real preferredWallpaperScale: Config.options.background.parallax.workspaceZoom
        property real effectiveWallpaperScale: 1 // Some reasonable init value, to be updated
        property int wallpaperWidth: screenScope.modelData.width // Some reasonable init value, to be updated
        property int wallpaperHeight: screenScope.modelData.height // Some reasonable init value, to be updated
        property real movableXSpace: ((wallpaperWidth / wallpaperToScreenRatio * effectiveWallpaperScale) - screenWidth) / 2
        property real movableYSpace: ((wallpaperHeight / wallpaperToScreenRatio * effectiveWallpaperScale) - screenHeight) / 2
        readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical
        // Colors
        readonly property real lockBlurProgress: Config.options.lock.blur.enable
            ? Math.max(0, Math.min(1, GlobalStates.screenLockBlurProgress))
            : 0
        property bool shouldBlur: lockBlurProgress > 0.001
        property color dominantColor: Appearance.colors.colPrimary // Default, to be changed
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Layer props
        screen: screenScope.modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        onWallpaperPathChanged: {
            if (bgRoot.wallpaperAnimationArmed && bgRoot.wallpaperPath.length > 0 && !bgRoot.wallpaperIsVideo && !bgRoot.wallpaperSafetyTriggered && bgRoot.displayedWallpaperPath.length > 0 && bgRoot.displayedWallpaperPath !== bgRoot.wallpaperPath) {
                if (bgRoot.wallpaperRevealActive)
                    bgRoot.queuedRevealWallpaperPath = bgRoot.wallpaperPath;
                else
                    bgRoot.beginWallpaperReveal(bgRoot.wallpaperPath);
            } else {
                bgRoot.commitWallpaperPath(bgRoot.wallpaperPath);
                bgRoot.updateZoomScale();
            }
            // Clock position gets updated after zoom scale is updated
        }
        Component.onCompleted: {
            displayedWallpaperPath = wallpaperPath
            wallpaperAnimationArmed = true
            updateZoomScale()
        }
        onPreferredWallpaperScaleChanged: bgRoot.updateZoomScale()
        onScreenWidthChanged: bgRoot.updateZoomScale()
        onScreenHeightChanged: bgRoot.updateZoomScale()

        function commitWallpaperPath(path) {
            wallpaperRevealAnimation.stop()
            displayedWallpaperPath = path
            revealWallpaperPath = ""
            queuedRevealWallpaperPath = ""
            wallpaperRevealActive = false
            wallpaperRevealPending = false
            wallpaperRevealWarming = false
            wallpaperRevealWarmupFrames = 0
            wallpaperRevealProgress = 1
        }

        function beginWallpaperReveal(path) {
            wallpaperRevealAnimation.stop()
            revealWallpaperPath = path
            wallpaperRevealActive = true
            wallpaperRevealPending = true
            wallpaperRevealWarming = false
            wallpaperRevealWarmupFrames = 0
            wallpaperRevealProgress = 0
            Qt.callLater(bgRoot.startWallpaperRevealIfReady)
        }

        function startWallpaperRevealIfReady() {
            if (!wallpaperRevealPending)
                return
            if (wallpaperReveal.status === Image.Ready) {
                wallpaperRevealPending = false
                wallpaperRevealWarming = true
                wallpaperRevealWarmupFrames = 0
                wallpaperRevealTexture.scheduleUpdate()
            } else if (wallpaperReveal.status === Image.Error) {
                commitWallpaperPath(revealWallpaperPath)
            }
        }

        function startWallpaperRevealAnimation() {
            if (!wallpaperRevealActive || revealWallpaperPath.length === 0 || wallpaperReveal.status !== Image.Ready)
                return
            wallpaperRevealTexture.scheduleUpdate()
            wallpaperRevealWarming = false
            wallpaperRevealWarmupFrames = 0
            wallpaperRevealProgress = 0
            wallpaperRevealAnimation.restart()
        }

        function finishWallpaperReveal() {
            const nextPath = queuedRevealWallpaperPath
            displayedWallpaperPath = revealWallpaperPath
            revealWallpaperPath = ""
            queuedRevealWallpaperPath = ""
            wallpaperRevealActive = false
            wallpaperRevealPending = false
            wallpaperRevealWarming = false
            wallpaperRevealWarmupFrames = 0
            wallpaperRevealProgress = 1
            updateZoomScale()
            if (nextPath.length > 0 && nextPath !== displayedWallpaperPath && nextPath === wallpaperPath && !wallpaperIsVideo && !wallpaperSafetyTriggered)
                Qt.callLater(() => bgRoot.beginWallpaperReveal(nextPath))
        }

        function startWallpaperPreloadWarmupIfReady() {
            if (!Wallpapers.preloadWallpaperPath || Wallpapers.preloadWallpaperPath.length === 0) {
                wallpaperPreloadWarming = false
                wallpaperPreloadWarmupFrames = 0
                return
            }
            if (wallpaperPreload.status === Image.Ready) {
                wallpaperPreloadWarmupFrames = 0
                wallpaperPreloadWarming = true
            }
        }

        // Wallpaper zoom scale
        function updateZoomScale() {
            if (!bgRoot.wallpaperPath || bgRoot.wallpaperPath.length === 0)
                return;
            getWallpaperSizeProc.path = bgRoot.wallpaperPath;
            getWallpaperSizeProc.running = true;
        }
        Process {
            id: getWallpaperSizeProc
            property string path: bgRoot.wallpaperPath
            command: ["magick", "identify", "-format", "%w %h", path]
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    const output = wallpaperSizeOutputCollector.text;
                    const [width, height] = output.split(" ").map(Number);
                    const [screenWidth, screenHeight] = [bgRoot.screenWidth, bgRoot.screenHeight];
                    if (!Number.isFinite(width) || width <= 0 || !Number.isFinite(height) || height <= 0) {
                        bgRoot.wallpaperWidth = Math.max(1, screenWidth);
                        bgRoot.wallpaperHeight = Math.max(1, screenHeight);
                        bgRoot.effectiveWallpaperScale = bgRoot.preferredWallpaperScale;
                        return;
                    }
                    bgRoot.wallpaperWidth = width;
                    bgRoot.wallpaperHeight = height;

                    if (width <= screenWidth || height <= screenHeight) {
                        // Undersized/perfectly sized wallpapers
                        bgRoot.effectiveWallpaperScale = Math.max(screenWidth / width, screenHeight / height);
                    } else {
                        // Oversized = can be zoomed for parallax, yay
                        bgRoot.effectiveWallpaperScale = Math.min(bgRoot.preferredWallpaperScale, width / screenWidth, height / screenHeight);
                    }
                }
            }
        }

        SequentialAnimation {
            id: wallpaperRevealAnimation
            NumberAnimation {
                target: bgRoot
                property: "wallpaperRevealProgress"
                from: 0
                to: 1
                duration: 1150
                easing.type: Easing.Linear
            }
            ScriptAction {
                script: bgRoot.finishWallpaperReveal()
            }
        }

        FrameAnimation {
            running: bgRoot.wallpaperRevealWarming
            onTriggered: {
                wallpaperRevealTexture.scheduleUpdate()
                bgRoot.wallpaperRevealWarmupFrames += 1
                if (bgRoot.wallpaperRevealWarmupFrames >= 3)
                    bgRoot.startWallpaperRevealAnimation()
            }
        }

        FrameAnimation {
            running: bgRoot.wallpaperPreloadWarming
            onTriggered: {
                bgRoot.wallpaperPreloadWarmupFrames += 1
                if (bgRoot.wallpaperPreloadWarmupFrames >= 3) {
                    bgRoot.wallpaperPreloadWarming = false
                    Wallpapers.markPreloadReady(Wallpapers.preloadWallpaperPath, bgRoot.monitor?.name ?? screenScope.modelData?.name ?? "")
                }
            }
        }

        Item {
            anchors.fill: parent
            clip: true

            Image {
                id: wallpaperPreload
                readonly property bool shouldPreload: Wallpapers.preloadWallpaperPath.length > 0 && Wallpapers.preloadWallpaperPath !== bgRoot.displayedWallpaperPath
                anchors.fill: parent
                visible: false
                asynchronous: true
                cache: true
                smooth: false
                source: shouldPreload ? Wallpapers.preloadWallpaperPath : ""
                fillMode: Image.PreserveAspectCrop
                transformOrigin: Item.Center
                scale: 1
                sourceSize {
                    width: bgRoot.screenWidth * bgRoot.monitorScale
                    height: bgRoot.screenHeight * bgRoot.monitorScale
                }
                onSourceChanged: bgRoot.startWallpaperPreloadWarmupIfReady()
                onStatusChanged: bgRoot.startWallpaperPreloadWarmupIfReady()
            }

            // Wallpaper
            StyledImage {
                id: wallpaper
                visible: opacity > 0
                opacity: (status === Image.Ready && !bgRoot.wallpaperIsVideo) ? 1 : 0
                cache: true
                smooth: false
                // Range = groups that workspaces span on
                property int chunkSize: Config?.options.bar.workspaces.shown ?? 10
                property int lower: Math.floor(bgRoot.firstWorkspaceId / chunkSize) * chunkSize
                property int upper: Math.ceil(bgRoot.lastWorkspaceId / chunkSize) * chunkSize
                property int range: upper - lower
                property real valueX: {
                    let result = 0.5;
                    if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                        result = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
                    }
                    if (Config.options.background.parallax.enableSidebar) {
                        result += (0.15 * GlobalStates.sidebarRightOpen - 0.15 * GlobalStates.sidebarLeftOpen);
                    }
                    return result;
                }
                property real valueY: {
                    let result = 0.5;
                    if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                        result = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
                    }
                    return result;
                }
                property real effectiveValueX: Math.max(0, Math.min(1, valueX))
                property real effectiveValueY: Math.max(0, Math.min(1, valueY))
                x: -(bgRoot.movableXSpace) - (effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace
                y: -(bgRoot.movableYSpace) - (effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace
                source: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.displayedWallpaperPath
                fillMode: Image.PreserveAspectCrop
                transformOrigin: Item.Center
                scale: 1
                Behavior on x {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                sourceSize {
                    width: bgRoot.screenWidth * bgRoot.effectiveWallpaperScale * bgRoot.monitorScale
                    height: bgRoot.screenHeight * bgRoot.effectiveWallpaperScale * bgRoot.monitorScale
                }
                width: bgRoot.wallpaperWidth / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
                height: bgRoot.wallpaperHeight / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
            }

            Item {
                id: wallpaperRevealSourceItem
                anchors.fill: parent
                visible: bgRoot.wallpaperRevealActive && bgRoot.revealWallpaperPath.length > 0

                Image {
                    id: wallpaperReveal
                    anchors.fill: parent
                    visible: true
                    opacity: 1
                    asynchronous: true
                    cache: true
                    smooth: false
                    source: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.revealWallpaperPath
                    fillMode: Image.PreserveAspectCrop
                    transformOrigin: Item.Center
                    scale: 1
                    sourceSize {
                        width: bgRoot.screenWidth * bgRoot.monitorScale
                        height: bgRoot.screenHeight * bgRoot.monitorScale
                    }
                    onStatusChanged: bgRoot.startWallpaperRevealIfReady()
                }
            }

            ShaderEffect {
                id: wallpaperRevealShader
                anchors.fill: parent
                visible: bgRoot.wallpaperRevealActive && wallpaperReveal.status === Image.Ready
                blending: true
                property variant source: wallpaperRevealTexture
                property vector2d screenSize: Qt.vector2d(width, height)
                property vector2d origin: Qt.vector2d(bgRoot.wallpaperRevealOriginX, bgRoot.wallpaperRevealOriginY)
                property real radius: bgRoot.wallpaperRevealRadius
                property real edge: bgRoot.wallpaperRevealEdge
                property real progress: bgRoot.wallpaperRevealProgress
                fragmentShader: "shaders/wallpaper_reveal.frag.qsb"
            }

            ShaderEffectSource {
                id: wallpaperRevealTexture
                visible: false
                sourceItem: wallpaperRevealSourceItem
                live: bgRoot.wallpaperRevealWarming
                hideSource: true
                recursive: false
            }

            Rectangle {
                id: tvWorkspaceBackground
                anchors.fill: parent
                visible: bgRoot.showingTvModeWorkspace
                opacity: visible ? 1 : 0
                color: bgRoot.showingTvAppWorkspace ? "#081F2D" : "#10131F"

                Behavior on opacity {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.46
                    height: width
                    radius: width / 2
                    color: bgRoot.showingTvAppWorkspace ? "#80D8FF" : "#D0BCFF"
                    opacity: 0.18
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.26
                    height: width
                    radius: width / 2
                    color: bgRoot.showingTvAppWorkspace ? "#003547" : "#332D41"
                    opacity: 0.88
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "tv"
                    iconSize: Math.min(parent.width, parent.height) * 0.18
                    fill: 1
                    color: bgRoot.showingTvAppWorkspace ? "#C2E8FF" : "#EADDFF"
                }
            }

            Loader {
                id: blurLoader
                // The lock surface already renders a full-screen blurred wallpaper.
                // Avoid stacking a second wallpaper blur underneath the lock screen.
                active: false
                anchors.fill: wallpaper
                scale: 1 + ((Config.options.lock.blur.extraZoom - 1) * bgRoot.lockBlurProgress)
                sourceComponent: Item {
                    ShaderEffectSource {
                        id: wallpaperTexture
                        visible: wallpaper.status === Image.Ready
                        live: true
                        hideSource: true
                        sourceItem: wallpaper
                        x: wallpaper.x
                        y: wallpaper.y
                        width: wallpaper.width
                        height: wallpaper.height
                    }

                    GaussianBlur {
                        visible: wallpaperTexture.visible
                        source: wallpaperTexture
                        x: wallpaper.x
                        y: wallpaper.y
                        width: wallpaper.width
                        height: wallpaper.height
                        radius: Config.options.lock.blur.radius * bgRoot.lockBlurProgress
                        samples: Math.max(1, Math.ceil(radius) * 2 + 1)
                        transparentBorder: true
                    }

                    Rectangle {
                        visible: wallpaperTexture.visible
                        x: wallpaper.x
                        y: wallpaper.y
                        width: wallpaper.width
                        height: wallpaper.height
                        opacity: bgRoot.lockBlurProgress
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                    }
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                anchors {
                    left: wallpaper.left
                    right: wallpaper.right
                    top: wallpaper.top
                    bottom: wallpaper.bottom
                    horizontalCenter: undefined
                    verticalCenter: undefined
                    readonly property real parallaxFactor: Config.options.background.parallax.widgetsFactor
                    leftMargin: {
                        const xOnWallpaper = bgRoot.movableXSpace;
                        const extraMove = (wallpaper.effectiveValueX * 2 * bgRoot.movableXSpace) * (parallaxFactor - 1);
                        return xOnWallpaper - extraMove;
                    }
                    topMargin: {
                        const yOnWallpaper = bgRoot.movableYSpace;
                        const extraMove = (wallpaper.effectiveValueY * 2 * bgRoot.movableYSpace) * (parallaxFactor - 1);
                        return yOnWallpaper - extraMove;
                    }
                    Behavior on leftMargin {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on topMargin {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
                width: wallpaper.width
                height: wallpaper.height
                states: State {
                    name: "centered"
                    when: GlobalStates.screenLocked || bgRoot.wallpaperSafetyTriggered
                    PropertyChanges {
                        target: widgetCanvas
                        width: parent.width
                        height: parent.height
                    }
                    AnchorChanges {
                        target: widgetCanvas
                        anchors {
                            left: undefined
                            right: undefined
                            top: undefined
                            bottom: undefined
                            horizontalCenter: parent.horizontalCenter
                            verticalCenter: parent.verticalCenter
                        }
                    }
                }
                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                    AnchorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                FadeLoader {
                    id: weatherWidgetLoader
                    shown: Config.options.background.widgets.weather.enable
                    sourceComponent: WeatherWidget {
                        placementPaused: bgRoot.wallpaperRevealActive || bgRoot.wallpaperRevealPending || bgRoot.wallpaperRevealWarming
                        screenWidth: bgRoot.screenWidth
                        screenHeight: bgRoot.screenHeight
                        scaledScreenWidth: bgRoot.screenWidth / bgRoot.effectiveWallpaperScale
                        scaledScreenHeight: bgRoot.screenHeight / bgRoot.effectiveWallpaperScale
                        wallpaperScale: bgRoot.effectiveWallpaperScale
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.clock.enable && !GlobalStates.screenLocked
                    sourceComponent: ClockWidget {
                        placementPaused: bgRoot.wallpaperRevealActive || bgRoot.wallpaperRevealPending || bgRoot.wallpaperRevealWarming
                        screenWidth: bgRoot.screenWidth
                        screenHeight: bgRoot.screenHeight
                        scaledScreenWidth: bgRoot.screenWidth / bgRoot.effectiveWallpaperScale
                        scaledScreenHeight: bgRoot.screenHeight / bgRoot.effectiveWallpaperScale
                        wallpaperScale: bgRoot.effectiveWallpaperScale
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                        avoidanceActive: weatherWidgetLoader.shown
                            && weatherWidgetLoader.item !== null
                            && weatherWidgetLoader.item.visible
                        avoidanceX: weatherWidgetLoader.item?.x ?? 0
                        avoidanceY: weatherWidgetLoader.item?.y ?? 0
                        avoidanceWidth: weatherWidgetLoader.item?.width ?? 0
                        avoidanceHeight: weatherWidgetLoader.item?.height ?? 0
                    }
                }
            }
        }
    }
}
}
