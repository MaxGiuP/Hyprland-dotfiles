import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft
import qs.modules.ii.sidebarRight.pomodoro
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io

// Small shell utilities exposed as real windows. They share the same services
// as their sidebar versions, so an active timer remains identical everywhere.
Scope {
    id: root

    function showWindow(window) {
        window.visible = true;
        window.raise();
        window.requestActivate();
    }

    function showCalculator() {
        root.showWindow(calculatorWindow);
        Qt.callLater(() => calculator.forceActiveFocus());
    }

    function showTimers() {
        root.showWindow(timersWindow);
        Qt.callLater(() => timers.forceActiveFocus());
    }

    function showDashboard(tab = 0) {
        dashboard.currentTab = Math.max(0, Math.min(4, Number(tab) || 0));
        root.showWindow(dashboardWindow);
    }

    component UtilityWindow: ApplicationWindow {
        visible: false
        color: Appearance.colors.colLayer0
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint

        onClosing: event => {
            event.accepted = false;
            visible = false;
        }

        Shortcut {
            sequence: "Escape"
            context: Qt.WindowShortcut
            onActivated: parent.visible = false
        }
    }

    UtilityWindow {
        id: calculatorWindow
        title: "Quickshell Calculator"
        width: 520
        height: 760
        minimumWidth: 440
        minimumHeight: 620

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0

            Calculator {
                id: calculator
                anchors.fill: parent
            }
        }
    }

    UtilityWindow {
        id: dashboardWindow
        title: "Quickshell System Dashboard"
        width: 980
        height: 760
        minimumWidth: 760
        minimumHeight: 580

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0

            SystemDashboard {
                id: dashboard
                anchors.fill: parent
                anchors.margins: 12
            }
        }
    }

    UtilityWindow {
        id: timersWindow
        title: "Quickshell Timers"
        width: 620
        height: 560
        minimumWidth: 500
        minimumHeight: 440

        Rectangle {
            anchors.fill: parent
            anchors.margins: 10
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    MaterialSymbol {
                        text: "timer"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        text: "Timers"
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: "Space: start/pause   R: reset   L: lap"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                PomodoroWidget {
                    id: timers
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    focus: true
                }
            }
        }
    }

    IpcHandler {
        target: "systemApps"

        function calculator(): void { root.showCalculator(); }
        function timers(): void { root.showTimers(); }
        function dashboard(): void { root.showDashboard(0); }
        function modes(): void { root.showDashboard(1); }
        function workspaces(): void { root.showDashboard(2); }
        function privacy(): void { root.showDashboard(3); }
        function widgets(): void { root.showDashboard(4); }
        function closeCalculator(): void { calculatorWindow.visible = false; }
        function closeTimers(): void { timersWindow.visible = false; }
        function closeDashboard(): void { dashboardWindow.visible = false; }
    }
}
