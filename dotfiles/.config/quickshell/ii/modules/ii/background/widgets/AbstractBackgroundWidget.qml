import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property int scaledScreenWidth
    required property int scaledScreenHeight
    required property real wallpaperScale
    property bool visibleWhenLocked: false
    property var configEntry: Config.options.background.widgets[configEntryName]
    property string placementStrategy: configEntry.placementStrategy
    width: implicitWidth
    height: implicitHeight
    readonly property real effectiveWidgetWidth: Math.max(implicitWidth, 1)
    readonly property real effectiveWidgetHeight: Math.max(implicitHeight, 1)
    property real targetX: Math.max(0, Math.min(configEntry.x, scaledScreenWidth - effectiveWidgetWidth))
    property real targetY : Math.max(0, Math.min(configEntry.y, scaledScreenHeight - effectiveWidgetHeight))
    x: targetX
    y: targetY
    visible: opacity > 0
    opacity: (GlobalStates.screenLocked && !visibleWhenLocked) ? 0 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: (draggable && containsPress) ? 1.05 : 1
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    draggable: placementStrategy === "free"
    onReleased: {
        root.targetX = root.x;
        root.targetY = root.y;
        configEntry.x = root.targetX;
        configEntry.y = root.targetY;
    }

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property color colText: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }

    property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
    property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    
    onWallpaperPathChanged: refreshPlacementIfNeeded()
    onPlacementStrategyChanged: refreshPlacementIfNeeded()
    onScaledScreenWidthChanged: refreshPlacementIfNeeded()
    onScaledScreenHeightChanged: refreshPlacementIfNeeded()
    onWallpaperScaleChanged: refreshPlacementIfNeeded()
    onEffectiveWidgetWidthChanged: refreshPlacementIfNeeded()
    onEffectiveWidgetHeightChanged: refreshPlacementIfNeeded()
    Connections {
        target: Config
        function onReadyChanged() { refreshPlacementIfNeeded() }
    }
    Component.onCompleted: Qt.callLater(root.refreshPlacementIfNeeded)
    function refreshPlacementIfNeeded() {
        if (!Config.ready) return;
        if (root.scaledScreenWidth <= 0 || root.scaledScreenHeight <= 0) return;
        if (root.effectiveWidgetWidth <= 0 || root.effectiveWidgetHeight <= 0) return;
        if (root.placementStrategy === "free" && !root.needsColText) return;
        placementRefreshDebounce.restart();
    }
    Timer {
        id: placementRefreshDebounce
        interval: 80
        repeat: false
        onTriggered: {
            leastBusyRegionProc.wallpaperPath = root.wallpaperPath;
            leastBusyRegionProc.running = false;
            leastBusyRegionProc.running = true;
        }
    }
    Process {
        id: leastBusyRegionProc
        property string wallpaperPath: root.wallpaperPath
        property int contentWidth: Math.max(1, Math.round(root.effectiveWidgetWidth))
        property int contentHeight: Math.max(1, Math.round(root.effectiveWidgetHeight))
        property int horizontalPadding: 200
        property int verticalPadding: 200
        command: [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh") // Comments to force the formatter to break lines
            , "--screen-width", Math.round(root.scaledScreenWidth) //
            , "--screen-height", Math.round(root.scaledScreenHeight) //
            , "--width", contentWidth //
            , "--height", contentHeight //
            , "--horizontal-padding", horizontalPadding //
            , "--vertical-padding", verticalPadding //
            , wallpaperPath //
            , ...(root.placementStrategy === "mostBusy" ? ["--busiest"] : [])
            // "--visual-output",
        ]
        stdout: StdioCollector {
            id: leastBusyRegionOutputCollector
            onStreamFinished: {
                const output = leastBusyRegionOutputCollector.text;
                // console.log("[Background] Least busy region output:", output)
                if (output.length === 0) return;
                const parsedContent = JSON.parse(output);
                root.dominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                if (root.placementStrategy === "free") return;
                const widgetWidth = root.effectiveWidgetWidth;
                const widgetHeight = root.effectiveWidgetHeight;
                const maxX = Math.max(0, root.scaledScreenWidth - widgetWidth);
                const maxY = Math.max(0, root.scaledScreenHeight - widgetHeight);
                root.targetX = Math.max(0, Math.min(maxX, parsedContent.center_x * root.wallpaperScale - widgetWidth / 2));
                root.targetY = Math.max(0, Math.min(maxY, parsedContent.center_y * root.wallpaperScale - widgetHeight / 2));
            }
        }
    }
}
