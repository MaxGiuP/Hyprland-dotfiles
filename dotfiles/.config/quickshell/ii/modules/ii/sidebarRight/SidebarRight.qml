import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property ShellScreen modelData
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            property bool sidebarOpen: GlobalStates.sidebarRightOpen && monitor?.name === GlobalStates.sidebarRightScreen
            property bool panelVisible: sidebarOpen

            Timer {
                id: panelUnmapTimer
                interval: 160
                repeat: false
                onTriggered: {
                    if (!screenScope.sidebarOpen)
                        screenScope.panelVisible = false;
                }
            }

            PanelWindow {
                id: panelWindow
                screen: screenScope.modelData
                visible: screenScope.panelVisible

                function hide() {
                    GlobalStates.closeSidebarRight();
                }

                exclusiveZone: 0
                exclusionMode: ExclusionMode.Normal
                implicitWidth: root.sidebarWidth
                implicitHeight: screen?.height ?? 2160
                WlrLayershell.namespace: "quickshell:sidebarRight"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                color: "transparent"
                mask: Region { item: sidebarContentLoader }

                anchors {
                    top: true
                    right: true
                }

                Connections {
                    target: screenScope
                    function onSidebarOpenChanged() {
                        if (screenScope.sidebarOpen) {
                            panelUnmapTimer.stop();
                            screenScope.panelVisible = true;
                            Qt.callLater(() => {
                                if (!screenScope.sidebarOpen)
                                    return;
                                GlobalFocusGrab.addDismissable(panelWindow);
                                sidebarContentLoader.forceActiveFocus();
                                sidebarContentLoader.item?.forceActiveFocus();
                            });
                        } else {
                            GlobalFocusGrab.removeDismissable(panelWindow);
                            // Keep the surface mapped until the 140 ms slide-out
                            // finishes, then release its compositor buffers.
                            screenScope.panelVisible = true;
                            panelUnmapTimer.restart();
                        }
                    }
                }
                Connections {
                    target: GlobalFocusGrab
                    function onDismissed() {
                        panelWindow.hide();
                    }
                }

                Loader {
                    id: sidebarContentLoader
                    // Keep it warm only when requested. Instantiating the full
                    // sidebar tree for every monitor was one of the shell's
                    // largest idle memory costs.
                    active: screenScope.panelVisible || Config.options.sidebar.keepRightSidebarLoaded
                    x: root.sidebarWidth
                    y: Appearance.sizes.hyprlandGapsOut
                    width: root.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                    height: parent.height - Appearance.sizes.barHeight - Appearance.sizes.hyprlandGapsOut

                    states: State {
                        name: "open"
                        when: screenScope.sidebarOpen
                        PropertyChanges { target: sidebarContentLoader; x: Appearance.sizes.elevationMargin }
                    }
                    transitions: [
                        Transition {
                            to: "open"
                            NumberAnimation {
                                property: "x"
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        },
                        Transition {
                            from: "open"
                            to: ""
                            NumberAnimation {
                                property: "x"
                                duration: 140
                                easing.type: Easing.InCubic
                            }
                        }
                    ]

                    focus: screenScope.sidebarOpen
                    activeFocusOnTab: true
                    TapHandler {
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onPressedChanged: {
                            if (pressed) {
                                sidebarContentLoader.forceActiveFocus();
                                sidebarContentLoader.item?.forceActiveFocus();
                            }
                        }
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            panelWindow.hide();
                        }
                    }

                    sourceComponent: SidebarRightContent {}
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarRight"

        function toggle(): void {
            GlobalStates.toggleSidebarRight();
        }

        function close(): void {
            GlobalStates.closeSidebarRight();
        }

        function open(): void {
            GlobalStates.openSidebarRight();
        }

        function timer(): void {
            GlobalStates.openTimer();
        }

        function calendar(): void {
            GlobalStates.openCalendar();
        }

        function todo(): void {
            GlobalStates.openTodo();
        }

        function newTask(): void {
            GlobalStates.openNewTask();
        }
    }

    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"

        onPressed: {
            GlobalStates.toggleSidebarRight();
        }
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"

        onPressed: {
            GlobalStates.openSidebarRight();
        }
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"

        onPressed: {
            GlobalStates.closeSidebarRight();
        }
    }
}
