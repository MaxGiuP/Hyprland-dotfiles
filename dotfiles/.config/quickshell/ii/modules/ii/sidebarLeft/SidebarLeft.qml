import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool pin: false

    Process {
        id: pinWithFunnyHyprlandWorkaroundProc
        property var hook: null
        property int cursorX
        property int cursorY
        function doIt() {
            command = ["hyprctl", "cursorpos"]
            hook = (output) => {
                cursorX = parseInt(output.split(",")[0]);
                cursorY = parseInt(output.split(",")[1]);
                doIt2();
            }
            running = true;
        }
        function doIt2() {
            command = ["bash", "-c", "hyprctl dispatch movecursor 9999 9999"];
            hook = () => { doIt3(); }
            running = true;
        }
        function doIt3() {
            root.pin = !root.pin;
            command = ["bash", "-c", `sleep 0.01; hyprctl dispatch movecursor ${cursorX} ${cursorY}`];
            hook = null;
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                pinWithFunnyHyprlandWorkaroundProc.hook(text);
            }
        }
    }

    function togglePin() {
        if (!root.pin) pinWithFunnyHyprlandWorkaroundProc.doIt();
        else root.pin = !root.pin;
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property ShellScreen modelData
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            property bool sidebarOpen: GlobalStates.sidebarLeftOpen && monitor?.name === GlobalStates.sidebarLeftScreen

            PanelWindow {
                id: panelWindow
                screen: screenScope.modelData
                visible: true

                property bool extend: false
                property real sidebarWidth: extend ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidth

                function hide() {
                    GlobalStates.closeSidebarLeft();
                }

                exclusionMode: ExclusionMode.Normal
                exclusiveZone: root.pin ? sidebarWidth : 0
                implicitWidth: Appearance.sizes.sidebarWidthExtended + Appearance.sizes.elevationMargin
                implicitHeight: screen?.height ?? 2160
                WlrLayershell.namespace: "quickshell:sidebarLeft"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                color: "transparent"

                anchors {
                    top: true
                    left: true
                }

                mask: Region {
                    item: sidebarLeftBackground
                }

                Connections {
                    target: screenScope
                    function onSidebarOpenChanged() {
                        if (screenScope.sidebarOpen) {
                            GlobalFocusGrab.addDismissable(panelWindow);
                            Qt.callLater(() => {
                                sidebarContent.focusActiveItem
                                    ? sidebarContent.focusActiveItem()
                                    : sidebarContent.forceActiveFocus();
                            });
                        } else {
                            GlobalFocusGrab.removeDismissable(panelWindow);
                        }
                    }
                }
                Connections {
                    target: GlobalFocusGrab
                    function onDismissed() {
                        panelWindow.hide();
                    }
                }

                StyledRectangularShadow {
                    target: sidebarLeftBackground
                    radius: sidebarLeftBackground.radius
                }
                Rectangle {
                    id: sidebarLeftBackground
                    focus: true
                    anchors.top: parent.top
                    anchors.topMargin: Appearance.sizes.hyprlandGapsOut
                    x: -panelWindow.implicitWidth
                    width: panelWindow.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                    height: parent.height - Appearance.sizes.barHeight - Appearance.sizes.hyprlandGapsOut
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

                    states: State {
                        name: "open"
                        when: screenScope.sidebarOpen
                        PropertyChanges { target: sidebarLeftBackground; x: Appearance.sizes.hyprlandGapsOut }
                    }
                    transitions: [
                        Transition {
                            to: "open"
                            NumberAnimation {
                                property: "x"
                                duration: 300
                                easing.type: Easing.OutCubic
                            }
                        },
                        Transition {
                            from: "open"
                            to: ""
                            NumberAnimation {
                                property: "x"
                                duration: 200
                                easing.type: Easing.InCubic
                            }
                        }
                    ]

                    Behavior on width {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onPressedChanged: {
                            if (pressed)
                                sidebarLeftBackground.forceActiveFocus();
                        }
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            panelWindow.hide();
                        }
                        if (event.modifiers === Qt.ControlModifier) {
                            if (event.key === Qt.Key_O) {
                                panelWindow.extend = !panelWindow.extend;
                            } else if (event.key === Qt.Key_P) {
                                root.togglePin();
                            }
                            event.accepted = true;
                        }
                    }

                    SidebarLeftContent {
                        id: sidebarContent
                        scopeRoot: panelWindow
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.toggleSidebarLeft();
        }

        function close(): void {
            GlobalStates.closeSidebarLeft();
        }

        function open(): void {
            GlobalStates.openSidebarLeft();
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: {
            GlobalStates.toggleSidebarLeft();
        }
    }

    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"

        onPressed: {
            GlobalStates.openSidebarLeft();
        }
    }

    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"

        onPressed: {
            GlobalStates.closeSidebarLeft();
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Detach left sidebar into a window/Attach it back"

        onPressed: {
            // Detach not supported with multi-monitor Variants layout
        }
    }
}
