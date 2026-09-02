pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
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

    PanelWindow {
        id: panelRoot
        required property var modelData
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        readonly property var monitorData: HyprlandData.monitors.find(m => m.name === monitor?.name)
        readonly property string visibleSpecialWorkspace: `${monitorData?.specialWorkspace?.name ?? ""}`
        readonly property string activeWorkspaceName: `${monitorData?.activeWorkspace?.name ?? ""}`
        readonly property bool showingTvWorkspace: visibleSpecialWorkspace === "special:tv" || (monitor?.name === "HDMI-A-2" && activeWorkspaceName === "21")
        readonly property bool showingTvAppWorkspace: visibleSpecialWorkspace === "special:tv-app"
        readonly property bool showingTvModeWorkspace: showingTvWorkspace || showingTvAppWorkspace

        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        StyledImage {
            anchors.fill: parent
            visible: !panelRoot.showingTvModeWorkspace
            source: Config.options.background.wallpaperPath
            fillMode: Image.PreserveAspectCrop
            cache: false
        }

        Rectangle {
            anchors.fill: parent
            visible: panelRoot.showingTvModeWorkspace
            color: panelRoot.showingTvAppWorkspace ? "#081F2D" : "#10131F"

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) * 0.46
                height: width
                radius: width / 2
                color: panelRoot.showingTvAppWorkspace ? "#80D8FF" : "#D0BCFF"
                opacity: 0.18
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) * 0.26
                height: width
                radius: width / 2
                color: panelRoot.showingTvAppWorkspace ? "#003547" : "#332D41"
                opacity: 0.88
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "tv"
                iconSize: Math.min(parent.width, parent.height) * 0.18
                fill: 1
                color: panelRoot.showingTvAppWorkspace ? "#C2E8FF" : "#EADDFF"
            }
        }
    }
}
