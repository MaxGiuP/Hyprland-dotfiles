import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    readonly property bool pinned: Config.options?.dock.pinnedOnStartup ?? false
    readonly property bool floatingDock: (Config.options?.dock.mode ?? "fixed") === "floating"
    readonly property bool flaredDockBase: Config.options?.dock.rounded ?? true
    readonly property real dockButtonInset: Appearance.sizes.hyprlandGapsOut + 5
    readonly property real dockButtonSize: Math.max(36, (Config.options?.dock.height ?? 70) - root.dockButtonInset * 2)
    readonly property real appIconSize: Math.max(26, Math.round(root.dockButtonSize * 0.9))
    readonly property real controlIconSize: Math.max(18, Math.round(root.appIconSize * 0.62))
    readonly property real edgeButtonVisualSize: Math.max(31, Math.round(root.appIconSize * 1.04))
    readonly property real dockContentPadding: Math.max(4, Math.round(root.appIconSize * 0.18))
    readonly property real dockSeparatorInset: Math.max(Appearance.rounding.small, Math.round(root.appIconSize * 0.26))
    readonly property real dockSeparatorWidth: Math.max(1, Math.round(root.appIconSize * 0.05))
    readonly property real controlIconVerticalOffset: 0
    readonly property real pinIconHorizontalOffset: Math.max(1, Math.round(root.appIconSize * 0.06))
    readonly property real drawerIconHorizontalOffset: root.pinIconHorizontalOffset
    readonly property real dockContentHorizontalOffset: 0
    readonly property real dockBlurRadius: 56
    readonly property real dockBlurTintAlpha: {
        if (root.dockBackgroundColor.a <= 0)
            return 0;
        return Math.max(0.50, Math.min(0.72, root.dockBackgroundColor.a - 0.08));
    }
    readonly property real dockFallbackTintAlpha: Math.min(0.9, root.dockBackgroundColor.a + 0.12)
    readonly property string dockWallpaperSource: {
        const wallpaperPath = Config.options.background.wallpaperPath ?? "";
        const isVideo = wallpaperPath.endsWith(".mp4")
            || wallpaperPath.endsWith(".webm")
            || wallpaperPath.endsWith(".mkv")
            || wallpaperPath.endsWith(".avi")
            || wallpaperPath.endsWith(".mov");
        const selectedPath = isVideo ? (Config.options.background.thumbnailPath ?? "") : wallpaperPath;
        return selectedPath.length > 0 ? Qt.resolvedUrl(selectedPath) : "";
    }
    readonly property color dockBackgroundColor: {
        if (!Config.options.bar.showBackground) return "transparent"
        const level = Config.options.bar.backgroundOpacity ?? 0
        if (level >= 2) return "transparent"
        if (level === 1) {
            const c = Appearance.colors.colLayer0
            return Qt.rgba(c.r, c.g, c.b, 0.5)
        }
        return Appearance.colors.colLayer0
    }
    readonly property color dockBorderColor: Appearance.colors.colLayer0Border

    Variants {
        // For each monitor
        model: Quickshell.screens

        PanelWindow {
            id: dockRoot
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            readonly property int activeWorkspaceId: monitor?.activeWorkspace?.id ?? -1
            readonly property bool activeWorkspaceEmpty: activeWorkspaceId === -1
                || HyprlandData.hyprlandClientsForWorkspace(activeWorkspaceId).length === 0
            readonly property real revealRegionHeight: Config.options?.dock.hoverToReveal
                ? Math.max(1, Config.options.dock.hoverRegionHeight ?? 2)
                : 0
            readonly property real hiddenDockOvershoot: Math.max(6, Appearance.sizes.hyprlandGapsOut + 2)
            readonly property real hiddenDockVisualOffset: dockRoot.reveal
                ? 0
                : (dockRoot.revealRegionHeight > 0
                    ? dockRoot.revealRegionHeight + dockRoot.hiddenDockOvershoot
                    : 0)

            property bool reveal: !launchpadOnThisScreen
                && (
                    root.pinned
                    || (Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse)
                    || dockApps.requestDockShow
                    || (GlobalStates.desktopDragActive && GlobalStates.desktopDragScreen === dockRoot.modelData.name)
                    || activeWorkspaceEmpty
                )

            anchors {
                bottom: true
                left: true
                right: true
            }

            readonly property bool launchpadOnThisScreen: GlobalStates.overviewDrawerMode
                || (GlobalStates.drawerOpen && dockRoot.modelData.name === GlobalStates.drawerScreen)
            exclusiveZone: (root.pinned && !launchpadOnThisScreen)
                ? implicitHeight - Appearance.sizes.hyprlandGapsOut - (Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut)
                : 0

            implicitWidth: dockBackground.implicitWidth
            WlrLayershell.namespace: "quickshell:dock"
            WlrLayershell.layer: WlrLayer.Top
            color: "transparent"

            Connections {
                target: GlobalStates
                function onOverviewDrawerModeChanged() {
                    if (GlobalStates.overviewDrawerMode) {
                        GlobalFocusGrab.addPersistent(dockRoot)
                    } else {
                        GlobalFocusGrab.removePersistent(dockRoot)
                    }
                }
            }

            implicitHeight: (Config.options?.dock.height ?? 70) + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut

            mask: Region {
                item: dockMouseArea
            }

            MouseArea {
                id: dockMouseArea
                height: parent.height
                anchors {
                    top: parent.top
                    topMargin: dockRoot.reveal
                        ? 0
                        : (Config.options?.dock.hoverToReveal
                            ? (dockRoot.implicitHeight - dockRoot.revealRegionHeight)
                            : (dockRoot.implicitHeight + 1))
                    horizontalCenter: parent.horizontalCenter
                }
                implicitWidth: dockHoverRegion.implicitWidth + Appearance.sizes.elevationMargin * 2
                hoverEnabled: true

                Behavior on anchors.topMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item {
                    id: dockHoverRegion
                    anchors.fill: parent
                    implicitWidth: dockBackground.implicitWidth

                    Item {
                        id: dockBackground
                        clip: !root.floatingDock
                        anchors {
                            bottom: parent.bottom
                            bottomMargin: -dockRoot.hiddenDockVisualOffset
                            horizontalCenter: parent.horizontalCenter
                        }

                        readonly property real fixedDockFlare: root.floatingDock
                            ? 0
                            : (root.flaredDockBase
                                ? Math.max(Appearance.rounding.normal, Math.round(root.appIconSize * 0.68))
                                : 0)
                        implicitWidth: Math.round(dockRow.implicitWidth + 5 * 2 + fixedDockFlare * 2)
                        height: Math.round(parent.height - Appearance.sizes.elevationMargin)

                        Behavior on anchors.bottomMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        StyledRectangularShadow {
                            target: dockShadowTarget
                            offset: Qt.vector2d(0.0, 0.0)
                            visible: root.floatingDock
                        }

                        Rectangle {
                            id: dockShadowTarget
                            visible: false
                            anchors.fill: dockVisualBackground
                            radius: dockVisualBackground.radius
                        }

                        Item {
                            id: dockVisualBackground
                            readonly property real radius: Appearance.rounding.large
                            readonly property real fixedDockFlare: dockBackground.fixedDockFlare
                            readonly property real fixedDockBaseOverlap: root.floatingDock
                                ? 0
                                : (root.flaredDockBase ? Math.round(fixedDockFlare * 0.06) : 0)
                            readonly property real fixedDockVisibleBottom: height - fixedDockBaseOverlap
                            layer.enabled: !root.floatingDock
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Appearance.colors.colShadow
                                shadowBlur: 0.96
                                shadowVerticalOffset: 8
                                shadowHorizontalOffset: 0
                            }
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.topMargin: Appearance.sizes.elevationMargin
                            anchors.bottomMargin: root.floatingDock
                                ? Appearance.sizes.hyprlandGapsOut
                                : -fixedDockBaseOverlap

                            Loader {
                                anchors.fill: parent
                                sourceComponent: root.floatingDock
                                    ? floatingDockBackground
                                    : (root.flaredDockBase ? fixedDockBackground : fixedStraightDockBackground)
                            }
                        }

                        component DockWallpaperBackdrop: Item {
                            Image {
                                id: dockWallpaper
                                visible: source.length > 0
                                x: -dockVisualBackground.x
                                y: dockRoot.height - (dockRoot.modelData?.height ?? dockRoot.height) - dockVisualBackground.y
                                width: dockRoot.modelData?.width ?? dockRoot.width
                                height: dockRoot.modelData?.height ?? dockRoot.height
                                source: root.dockWallpaperSource
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                                asynchronous: true
                                smooth: true
                                antialiasing: true
                                sourceSize.width: Math.max(1, Math.round(width * (dockRoot.monitor?.scale ?? 1)))
                                sourceSize.height: Math.max(1, Math.round(height * (dockRoot.monitor?.scale ?? 1)))
                            }

                            ShaderEffectSource {
                                id: dockWallpaperTexture
                                visible: dockWallpaper.status === Image.Ready
                                live: true
                                hideSource: true
                                sourceItem: dockWallpaper
                                x: dockWallpaper.x
                                y: dockWallpaper.y
                                width: dockWallpaper.width
                                height: dockWallpaper.height
                            }

                            GaussianBlur {
                                id: dockWallpaperBlur
                                visible: dockWallpaperTexture.visible
                                source: dockWallpaperTexture
                                x: dockWallpaper.x
                                y: dockWallpaper.y
                                width: dockWallpaper.width
                                height: dockWallpaper.height
                                radius: root.dockBlurRadius
                                samples: Math.max(1, Math.ceil(radius) * 2 + 1)
                                transparentBorder: true
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(
                                    root.dockBackgroundColor.r,
                                    root.dockBackgroundColor.g,
                                    root.dockBackgroundColor.b,
                                    dockWallpaperBlur.visible ? root.dockBlurTintAlpha : root.dockFallbackTintAlpha
                                )
                            }
                        }

                        Component {
                            id: floatingDockBackground

                            Item {
                                id: floatingDockSurface

                                Item {
                                    anchors.fill: parent
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: floatingDockSurface.width
                                            height: floatingDockSurface.height
                                            radius: dockVisualBackground.radius
                                        }
                                    }

                                    DockWallpaperBackdrop {
                                        anchors.fill: parent
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    border.width: 1
                                    border.color: root.dockBorderColor
                                    radius: dockVisualBackground.radius
                                }
                            }
                        }

                        Component {
                            id: fixedStraightDockBackground

                            Item {
                                id: fixedStraightDockSurface

                                Item {
                                    anchors.fill: parent
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Shape {
                                            width: fixedStraightDockSurface.width
                                            height: fixedStraightDockSurface.height
                                            preferredRendererType: Shape.CurveRenderer

                                            ShapePath {
                                                fillColor: "white"
                                                strokeColor: "transparent"
                                                strokeWidth: 0

                                                startX: dockVisualBackground.radius
                                                startY: 0

                                                PathLine {
                                                    x: dockVisualBackground.width - dockVisualBackground.radius
                                                    y: 0
                                                }
                                                PathArc {
                                                    x: dockVisualBackground.width
                                                    y: dockVisualBackground.radius
                                                    radiusX: dockVisualBackground.radius
                                                    radiusY: dockVisualBackground.radius
                                                    direction: PathArc.Clockwise
                                                }
                                                PathLine {
                                                    x: dockVisualBackground.width
                                                    y: dockVisualBackground.fixedDockVisibleBottom
                                                }
                                                PathLine {
                                                    x: 0
                                                    y: dockVisualBackground.fixedDockVisibleBottom
                                                }
                                                PathLine {
                                                    x: 0
                                                    y: dockVisualBackground.radius
                                                }
                                                PathArc {
                                                    x: dockVisualBackground.radius
                                                    y: 0
                                                    radiusX: dockVisualBackground.radius
                                                    radiusY: dockVisualBackground.radius
                                                    direction: PathArc.Clockwise
                                                }
                                            }
                                        }
                                    }

                                    DockWallpaperBackdrop {
                                        anchors.fill: parent
                                    }
                                }

                                Shape {
                                    anchors.fill: parent
                                    preferredRendererType: Shape.CurveRenderer

                                    ShapePath {
                                        fillColor: "transparent"
                                        strokeColor: root.dockBorderColor
                                        strokeWidth: 1

                                        startX: dockVisualBackground.radius
                                        startY: 0

                                        PathLine {
                                            x: dockVisualBackground.width - dockVisualBackground.radius
                                            y: 0
                                        }
                                        PathArc {
                                            x: dockVisualBackground.width
                                            y: dockVisualBackground.radius
                                            radiusX: dockVisualBackground.radius
                                            radiusY: dockVisualBackground.radius
                                            direction: PathArc.Clockwise
                                        }
                                        PathLine {
                                            x: dockVisualBackground.width
                                            y: dockVisualBackground.fixedDockVisibleBottom
                                        }
                                        PathLine {
                                            x: 0
                                            y: dockVisualBackground.fixedDockVisibleBottom
                                        }
                                        PathLine {
                                            x: 0
                                            y: dockVisualBackground.radius
                                        }
                                        PathArc {
                                            x: dockVisualBackground.radius
                                            y: 0
                                            radiusX: dockVisualBackground.radius
                                            radiusY: dockVisualBackground.radius
                                            direction: PathArc.Clockwise
                                        }
                                    }
                                }
                            }
                        }

                        Component {
                            id: fixedDockBackground

                            Item {
                                id: fixedDockSurface

                                Item {
                                    anchors.fill: parent
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Shape {
                                            width: fixedDockSurface.width
                                            height: fixedDockSurface.height
                                            preferredRendererType: Shape.CurveRenderer

                                            ShapePath {
                                                fillColor: "white"
                                                strokeColor: "transparent"
                                                strokeWidth: 0

                                                startX: dockVisualBackground.fixedDockFlare + dockVisualBackground.radius
                                                startY: 0

                                                PathLine {
                                                    x: dockVisualBackground.width
                                                        - dockVisualBackground.fixedDockFlare
                                                        - dockVisualBackground.radius
                                                    y: 0
                                                }
                                                PathArc {
                                                    x: dockVisualBackground.width - dockVisualBackground.fixedDockFlare
                                                    y: dockVisualBackground.radius
                                                    radiusX: dockVisualBackground.radius
                                                    radiusY: dockVisualBackground.radius
                                                    direction: PathArc.Clockwise
                                                }
                                                PathLine {
                                                    x: dockVisualBackground.width - dockVisualBackground.fixedDockFlare
                                                    y: dockVisualBackground.fixedDockVisibleBottom - dockVisualBackground.fixedDockFlare
                                                }
                                                PathArc {
                                                    x: dockVisualBackground.width + 1
                                                    y: dockVisualBackground.fixedDockVisibleBottom
                                                    radiusX: dockVisualBackground.fixedDockFlare
                                                    radiusY: dockVisualBackground.fixedDockFlare
                                                    direction: PathArc.Counterclockwise
                                                }
                                                PathLine {
                                                    x: 0
                                                    y: dockVisualBackground.fixedDockVisibleBottom
                                                }
                                                PathArc {
                                                    x: dockVisualBackground.fixedDockFlare
                                                    y: dockVisualBackground.fixedDockVisibleBottom - dockVisualBackground.fixedDockFlare
                                                    radiusX: dockVisualBackground.fixedDockFlare
                                                    radiusY: dockVisualBackground.fixedDockFlare
                                                    direction: PathArc.Counterclockwise
                                                }
                                                PathLine {
                                                    x: dockVisualBackground.fixedDockFlare
                                                    y: dockVisualBackground.radius
                                                }
                                                PathArc {
                                                    x: dockVisualBackground.fixedDockFlare + dockVisualBackground.radius
                                                    y: 0
                                                    radiusX: dockVisualBackground.radius
                                                    radiusY: dockVisualBackground.radius
                                                    direction: PathArc.Clockwise
                                                }
                                            }
                                        }
                                    }

                                    DockWallpaperBackdrop {
                                        anchors.fill: parent
                                    }
                                }

                                Shape {
                                    anchors.fill: parent
                                    preferredRendererType: Shape.CurveRenderer

                                    ShapePath {
                                        fillColor: "transparent"
                                        strokeColor: root.dockBorderColor
                                        strokeWidth: 1

                                        startX: dockVisualBackground.fixedDockFlare + dockVisualBackground.radius
                                        startY: 0

                                        PathLine {
                                            x: dockVisualBackground.width
                                                - dockVisualBackground.fixedDockFlare
                                                - dockVisualBackground.radius
                                            y: 0
                                        }
                                        PathArc {
                                            x: dockVisualBackground.width - dockVisualBackground.fixedDockFlare
                                            y: dockVisualBackground.radius
                                            radiusX: dockVisualBackground.radius
                                            radiusY: dockVisualBackground.radius
                                            direction: PathArc.Clockwise
                                        }
                                        PathLine {
                                            x: dockVisualBackground.width - dockVisualBackground.fixedDockFlare
                                            y: dockVisualBackground.fixedDockVisibleBottom - dockVisualBackground.fixedDockFlare
                                        }
                                        PathArc {
                                            x: dockVisualBackground.width + 1
                                            y: dockVisualBackground.fixedDockVisibleBottom
                                            radiusX: dockVisualBackground.fixedDockFlare
                                            radiusY: dockVisualBackground.fixedDockFlare
                                            direction: PathArc.Counterclockwise
                                        }
                                        PathLine {
                                            x: 0
                                            y: dockVisualBackground.fixedDockVisibleBottom
                                        }
                                        PathArc {
                                            x: dockVisualBackground.fixedDockFlare
                                            y: dockVisualBackground.fixedDockVisibleBottom - dockVisualBackground.fixedDockFlare
                                            radiusX: dockVisualBackground.fixedDockFlare
                                            radiusY: dockVisualBackground.fixedDockFlare
                                            direction: PathArc.Counterclockwise
                                        }
                                        PathLine {
                                            x: dockVisualBackground.fixedDockFlare
                                            y: dockVisualBackground.radius
                                        }
                                        PathArc {
                                            x: dockVisualBackground.fixedDockFlare + dockVisualBackground.radius
                                            y: 0
                                            radiusX: dockVisualBackground.radius
                                            radiusY: dockVisualBackground.radius
                                            direction: PathArc.Clockwise
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            id: dockRow
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.horizontalCenterOffset: root.dockContentHorizontalOffset
                            spacing: 3
                            property real padding: root.dockContentPadding

                            DockButton {
                                id: pinDockButton
                                visualSize: root.edgeButtonVisualSize
                                Layout.fillHeight: true
                                Layout.topMargin: Appearance.sizes.hyprlandGapsOut
                                toggled: root.pinned
                                onClicked: Config.options.dock.pinnedOnStartup = !Config.options.dock.pinnedOnStartup
                                topInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                bottomInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: root.pinIconHorizontalOffset
                                    anchors.verticalCenterOffset: root.controlIconVerticalOffset
                                    text: "keep"
                                    iconSize: root.controlIconSize
                                    color: pinDockButton.toggled ? pinDockButton.colForegroundToggled : Appearance.colors.colOnLayer0
                                }
                            }

                            DockSeparator {
                                separatorPadding: root.dockSeparatorInset
                                separatorThickness: root.dockSeparatorWidth
                            }

                            DockApps {
                                id: dockApps
                                buttonPadding: dockRow.padding
                            }

                            DockSeparator {
                                separatorPadding: root.dockSeparatorInset
                                separatorThickness: root.dockSeparatorWidth
                            }

                            DockButton {
                                id: drawerDockButton
                                visualSize: root.edgeButtonVisualSize
                                Layout.fillHeight: true
                                Layout.topMargin: Appearance.sizes.hyprlandGapsOut
                                onClicked: GlobalStates.toggleOverviewDrawer()
                                topInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                bottomInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: root.drawerIconHorizontalOffset
                                    anchors.verticalCenterOffset: root.controlIconVerticalOffset
                                    text: "apps"
                                    iconSize: root.controlIconSize
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
