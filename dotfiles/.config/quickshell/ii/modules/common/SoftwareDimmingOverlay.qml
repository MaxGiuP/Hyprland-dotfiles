import qs
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dimWindow
            required property ShellScreen modelData
            readonly property var brightnessMonitor: Brightness.getMonitorForScreen(modelData)
            readonly property real minimumVisibleBrightness: 0.25
            readonly property real dimOpacity: {
                if (!(brightnessMonitor?.usesSoftwareDimming ?? false))
                    return 0;

                const value = brightnessMonitor?.multipliedBrightness ?? 1;
                return Math.max(0, Math.min(1 - minimumVisibleBrightness, 1 - value));
            }

            screen: modelData
            visible: dimOpacity > 0.001
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "quickshell:softwareDimming"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            mask: Region {
                item: null
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: dimWindow.dimOpacity
            }
        }
    }
}
