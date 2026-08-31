pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: bar
    property bool showBarBackground: Config.options.bar.showBackground && (Config.options.bar.backgroundOpacity ?? 0) < 2

    Variants {
        // For each monitor
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }
        Scope {
            id: screenScope
            required property ShellScreen modelData

            LazyLoader {
                id: barLoader
                active: GlobalStates.barOpen
                component: Scope {
                PanelWindow { // Exclusive-zone carrier; intentionally not visible or interactive.
                    id: barReservation
                    screen: screenScope.modelData
                    visible: barRoot.visible
                    exclusiveZone: barRoot.desiredExclusiveZone
                    implicitHeight: barRoot.implicitHeight
                    WlrLayershell.namespace: "quickshell:bar-reservation"
                    color: "transparent"

                    anchors {
                        top: !Config.options.bar.bottom
                        bottom: Config.options.bar.bottom
                        left: true
                        right: true
                    }

                    mask: Region {}
                }

                PanelWindow { // Bar window
                id: barRoot
                screen: screenScope.modelData
                readonly property string screenName: screenScope.modelData?.name ?? ""
                readonly property bool tvOutput: screenName === "HDMI-A-2"
                readonly property bool fullscreenOnMonitor: HyprlandData.activeWorkspaceHasFullscreenForMonitor(screenName)
                readonly property bool suppressForFullscreen: HyprlandData.monitorShouldSuppressShell(screenName)
                readonly property bool tvSpecialVisible: tvOutput && HyprlandData.monitorShowsTvSpecialWorkspace(screenName)
                readonly property bool hideWhenFullscreen: Config.options.bar.hideWhenFullscreen ?? false
                visible: !tvSpecialVisible && (!hideWhenFullscreen || !suppressForFullscreen)
                readonly property bool topBarVisible: !Config.options.bar.bottom
                    && visible
                    && (!hideWhenFullscreen || !fullscreenOnMonitor)
                    && !launchpadOnThisScreen
                    && (!Config?.options.bar.autoHide.enable || mustShow)
                readonly property real topBarClearance: topBarVisible
                    ? (Appearance.sizes.baseBarHeight
                        + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0))
                    : Appearance.sizes.hyprlandGapsOut

                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: {
                        barRoot.superShow = true
                    }
                }
                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
                        if (GlobalStates.superDown) showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            barRoot.superShow = false;
                        }
                    }
                }
                property bool superShow: false
                readonly property bool launchpadOnThisScreen: GlobalStates.drawerOpen && screenScope.modelData.name === GlobalStates.drawerScreen
                property bool mustShow: (hoverRegion.containsMouse || superShow) && !launchpadOnThisScreen
                readonly property int desiredExclusiveZone: ((!visible) || launchpadOnThisScreen || (hideWhenFullscreen && fullscreenOnMonitor) || (Config?.options.bar.autoHide.enable && (!mustShow || !Config?.options.bar.autoHide.pushWindows))) ? 0 :
                    Appearance.sizes.baseBarHeight + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                // Keep the bar fixed to the monitor edges while side panels
                // add or remove their own exclusive zones.
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell:bar"
                implicitHeight: Appearance.sizes.barHeight + Appearance.rounding.screenRounding
                mask: Region {
                    item: hoverMaskRegion
                }
                color: "transparent"

                // Positioning
                anchors {
                    top: !Config.options.bar.bottom
                    bottom: Config.options.bar.bottom
                    left: true
                    right: true
                }

                margins {
                    right: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                    bottom: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1
                }

                // Include in focus grab
                Component.onCompleted: {
                    GlobalFocusGrab.addPersistent(barRoot);
                    GlobalStates.setBarTopClearance(screenScope.modelData.name, barRoot.topBarClearance);
                }

                Component.onDestruction: {
                    GlobalFocusGrab.removePersistent(barRoot);
                    GlobalStates.clearBarTopClearance(screenScope.modelData.name);
                }

                onTopBarClearanceChanged: {
                    GlobalStates.setBarTopClearance(screenScope.modelData.name, barRoot.topBarClearance);
                }

                MouseArea  {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors {
                        fill: parent
                        rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * 1
                        bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * 1
                    }

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            fill: barContent
                            topMargin: -Config.options.bar.autoHide.hoverRegionWidth
                            bottomMargin: -Config.options.bar.autoHide.hoverRegionWidth
                        }
                    }

                    BarContent {
                        id: barContent
                        screen: screenScope.modelData
                        
                        implicitHeight: Appearance.sizes.barHeight
                        anchors {
                            right: parent.right
                            left: parent.left
                            top: parent.top
                            bottom: undefined
                            leftMargin: 0
                            topMargin: ((Config?.options.bar.autoHide.enable && !barRoot.mustShow) || barRoot.launchpadOnThisScreen) ? -Appearance.sizes.barHeight : 0
                            bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1
                            rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                        }
                        Behavior on anchors.topMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on anchors.bottomMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: parent.bottom
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.leftMargin: 0
                                anchors.topMargin: 0
                                anchors.bottomMargin: ((Config?.options.bar.autoHide.enable && !barRoot.mustShow) || barRoot.launchpadOnThisScreen) ? -Appearance.sizes.barHeight : 0
                                anchors.rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                            }
                        }
                    }

                    // Round decorators
                    Loader {
                        id: roundDecorators
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: barContent.bottom
                            bottom: undefined
                            leftMargin: 0
                            rightMargin: 0
                        }
                        height: Appearance.rounding.screenRounding
                        active: showBarBackground && Config.options.bar.cornerStyle === 0 // Hug

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: barContent.top
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: leftCorner
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: parent.left
                                }

                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colLayer0 : "transparent"

                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        leftCorner.corner: RoundCorner.CornerEnum.BottomLeft
                                    }
                                }
                            }
                            RoundCorner {
                                id: rightCorner
                                anchors {
                                    right: parent.right
                                    top: !Config.options.bar.bottom ? parent.top : undefined
                                    bottom: Config.options.bar.bottom ? parent.bottom : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colLayer0 : "transparent"

                                corner: RoundCorner.CornerEnum.TopRight
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        rightCorner.corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
            }
        }
        }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            GlobalStates.barOpen = !GlobalStates.barOpen
        }

        function close(): void {
            GlobalStates.barOpen = false
        }

        function open(): void {
            GlobalStates.barOpen = true
        }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }
    }

    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            GlobalStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            GlobalStates.barOpen = false;
        }
    }
}
