import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks

Scope {
    id: root

    readonly property string focusedMonitorName: HyprlandData.eventFocusedMonitorName
        || HyprlandData.monitors.find(monitor => monitor.focused)?.name
        || Hyprland.focusedMonitor?.name
        || ""
    property var focusedScreen: Quickshell.screens.find(screen => screen.name === root.focusedMonitorName)
    property var indicatorScreen: root.currentIndicator === "brightness"
        ? (Brightness.lastChangedMonitor?.screen ?? root.focusedScreen)
        : root.focusedScreen
    property string currentIndicator: "volume"
    property var indicators: [
        {
            id: "volume",
            sourceUrl: "VolumeOSD.qml",
            globalStateValue: "osdVolumeOpen"
        },
        {
            id: "brightness",
            sourceUrl: "BrightnessOSD.qml",
            globalStateValue: "osdBrightnessOpen"
        },
    ]

    function triggerBrightnessOsd() {
        root.currentIndicator = "brightness";
        GlobalStates.osdBrightnessOpen = true;
    }

    function triggerVolumeOSD() {
        root.currentIndicator = "volume";
        GlobalStates.osdVolumeOpen = true;
    }

    // Listen to brightness changes
    Connections {
        target: Brightness
        function onBrightnessChanged() {
            root.triggerBrightnessOsd();
        }
    }

    // Listen to volume changes
    Connections {
        target: Audio
        function onValueChanged() {
            if (Audio.ready)
                root.triggerVolumeOSD();
        }
        function onMutedChanged() {
            if (Audio.ready)
                root.triggerVolumeOSD();
        }
    }

    // The actual thing
    Variants {
        model: Quickshell.screens

        Loader {
            id: panelLoader
            required property ShellScreen modelData
            active: (GlobalStates.osdVolumeOpen || GlobalStates.osdBrightnessOpen)
                && modelData.name === root.indicatorScreen?.name
            sourceComponent: PanelWindow {
                id: panelWindow
                screen: panelLoader.modelData

            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:wOnScreenDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: !Config.options.waffles.bar.bottom
                bottom: Config.options.waffles.bar.bottom
            }
            mask: Region {
                item: osdIndicatorLoader
            }

            implicitWidth: osdIndicatorLoader.implicitWidth
            implicitHeight: osdIndicatorLoader.implicitHeight

            Loader {
                id: osdIndicatorLoader
                anchors.fill: parent
                source: root.indicators.find(i => i.id === root.currentIndicator)?.sourceUrl

                Connections {
                    target: osdIndicatorLoader.item
                    function onClosed() {
                        GlobalStates[root.indicators.find(i => i.id === root.currentIndicator)?.globalStateValue] = false;
                    }
                }

                Behavior on source {
                    id: switchBehavior

                    SequentialAnimation {
                        id: switchAnim
                        // Animate close of current indicator
                        ScriptAction {
                            script: {
                                osdIndicatorLoader.item.close();
                            }
                        }
                        // Wait for close anim
                        PauseAnimation {
                            duration: osdIndicatorLoader.item.closeAnimDuration
                        }
                        PropertyAction {} // The source change happens here
                    }
                }
            }
            }
        }
    }

    IpcHandler {
        target: "osd"

        function trigger() {
            root.trigger();
        }
    }

    GlobalShortcut {
        name: "osdTrigger"
        description: "Triggers OSD display"

        onPressed: root.trigger()
    }
}
