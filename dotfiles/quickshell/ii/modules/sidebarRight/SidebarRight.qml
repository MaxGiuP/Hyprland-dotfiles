import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.sidebarRight.quickToggles
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 12
    property string settingsQmlPath: Quickshell.shellPath("settings.qml")

    property int updateCount: -1

    function refreshUpdateCount() {
        // recreate a short-lived Process to check updates
        updatesLoader.active = false
        updatesLoader.active = true
    }


    PanelWindow {
        id: sidebarRoot
        visible: GlobalStates.sidebarRightOpen

        function hide() {
            GlobalStates.sidebarRightOpen = false
        }

        exclusiveZone: 0
        implicitWidth: sidebarWidth
        WlrLayershell.namespace: "quickshell:sidebarRight"
        // Hyprland 0.49: Focus is always exclusive and setting this breaks mouse focus grab
        // WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"

        anchors {
            top: true
            right: true
            bottom: true
        }

        HyprlandFocusGrab {
            id: grab
            windows: [ sidebarRoot ]
            active: GlobalStates.sidebarRightOpen
            onCleared: () => {
                if (!active) sidebarRoot.hide()
            }
        }

        Loader {
            id: sidebarContentLoader
            active: GlobalStates.sidebarRightOpen || Config?.options.sidebar.keepRightSidebarLoaded
            anchors {
                fill: parent
                margins: Appearance.sizes.hyprlandGapsOut
                leftMargin: Appearance.sizes.elevationMargin
            }
            width: sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
            height: parent.height - Appearance.sizes.hyprlandGapsOut * 2

            focus: GlobalStates.sidebarRightOpen
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape) {
                    sidebarRoot.hide();
                }
            }

            sourceComponent: Item {
                implicitHeight: sidebarRightBackground.implicitHeight
                implicitWidth: sidebarRightBackground.implicitWidth

                StyledRectangularShadow {
                    target: sidebarRightBackground
                }
                Rectangle {
                    id: sidebarRightBackground

                    anchors.fill: parent
                    implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
                    implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: sidebarPadding
                        spacing: sidebarPadding

                        RowLayout {
                            Layout.fillHeight: false
                            spacing: 4
                            Layout.margins: 5
                            Layout.topMargin: 5
                            Layout.bottomMargin: 0

                            CustomIcon {
                                id: distroIcon
                                width: 25
                                height: 25
                                source: SystemInfo.distroIcon
                                colorize: true
                                color: Appearance.colors.colOnLayer0
                            }

                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer0
                                // text: Translation.tr("Up %1").arg(DateTime.uptime).arg(root.updateCount >= 0 ? root.updateCount : "?")

                                text: Translation.tr("Up %1").arg(DateTime.uptime.replace("d", Translation.tr("days").charAt(0)).replace("h", Translation.tr("hours").charAt(0)).replace("m", Translation.tr("minutes").charAt(0)).arg(root.updateCount >= 0 ? root.updateCount : "?"))

                                textFormat: Text.MarkdownText
                            }


                            Item {
                                Layout.fillWidth: true
                            }

                            ButtonGroup {
                                QuickToggleButton {
                                    toggled: false
                                    buttonIcon: "update"
                                    onClicked: {
                                        const t = "QSUpdate";
                                        const s = "/home/linmax/.config/hypr/custom/scripts/update.sh";

                                        // One single exec string; no bash -lc; use absolute kitty path if needed
                                        Quickshell.execDetached([
                                            "hyprctl", "dispatch", "exec",
                                            `[float;size 1000 750;center] /usr/bin/kitty -T ${t} ${s}`
                                        ]);
                                        GlobalStates.sidebarRightOpen = false
                                        // start watcher
                                        updateWatcher.title = t;
                                        updateWatcher.seenOnce = false;
                                        updatePoll.running = true;
                                    }

                                    
                                    StyledToolTip {
                                        verticalPadding: 3
                                        content: Translation.tr("Update System")
                                    }
                                }
                                QuickToggleButton {
                                    toggled: false
                                    buttonIcon: "restart_alt"
                                        onClicked: {
                                        // reload Hyprland first
                                        Hyprland.dispatch("reload")
                                        Quickshell.execDetached([
                                            "/usr/bin/sh","-lc",
                                            "~/.config/hypr/custom/scripts/restart_quickshell.sh"
                                        ])

                                    }
                                    StyledToolTip {
                                        verticalPadding: 3
                                        content: Translation.tr("Reload Hyprland & Quickshell")
                                    }
                                }
                                QuickToggleButton {
                                    toggled: false
                                    buttonIcon: "settings"
                                    onClicked: {
                                        GlobalStates.sidebarRightOpen = false
                                        Quickshell.execDetached(["qs", "-p", root.settingsQmlPath])
                                    }
                                    StyledToolTip {
                                        verticalPadding: 3
                                        content: Translation.tr("Settings")
                                    }
                                }
                                QuickToggleButton {
                                    toggled: false
                                    buttonIcon: "power_settings_new"
                                    onClicked: {
                                        GlobalStates.sessionOpen = true
                                    }
                                    StyledToolTip {
                                        verticalPadding: 3
                                        content: Translation.tr("Session")
                                    }
                                }
                            }
                        }

                        ButtonGroup {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 5
                            padding: 5
                            color: Appearance.colors.colLayer1

                            NetworkToggle {}
                            BluetoothToggle {}
                            NightLight {}
                            GameMode {}
                            IdleInhibitor {}
                            EasyEffectsToggle {}
                            CloudflareWarp {}
                        }

                        // Center widget group
                        CenterWidgetGroup {
                            focus: sidebarRoot.visible
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                        }

                        BottomWidgetGroup {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillHeight: false
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                        }
                    }
                }
            }
        }
    }

    // --- watcher state
    Item {
        id: updateWatcher
        property string title: "QSUpdate"
        property bool seenOnce: false
    }

    // Poll every 300ms until the window appears, then until it disappears
    Timer {
        id: updatePoll
        interval: 300
        repeat: true
        running: false
        onTriggered: {
            if (!hyprClients.running) {
                hyprClients.buf = "";
                hyprClients.running = true;
            }
        }
    }

    // Query Hyprland clients (JSON) and parse in JS (no shells)
    Process {
        id: hyprClients
        command: ["hyprctl", "-j", "clients"]   // if needed, change to "/usr/bin/hyprctl"
        property string buf: ""
        stdout: SplitParser { onRead: data => hyprClients.buf += data }
        onExited: {
            const txt = hyprClients.buf; hyprClients.buf = "";
            const found = txt.indexOf(`"title": "${updateWatcher.title}"`) !== -1;

            if (!updateWatcher.seenOnce) {
                if (found) updateWatcher.seenOnce = true;
            } else {
                if (!found) {
                    updatePoll.running = false;
                    root.refreshUpdateCount();
                }
            }
        }
    }

    Component {
        id: updatesComponent
        Process {
            // Sum pacman, flatpak, yay, paru if available. Output a single integer.
            command: ["/bin/bash", "-lc", `
                p=0; f=0; y=0; r=0;
                command -v checkupdates >/dev/null 2>&1 && p=$(checkupdates 2>/dev/null | wc -l) || true
                command -v flatpak     >/dev/null 2>&1 && f=$(flatpak remote-ls --updates 2>/dev/null | wc -l) || true
                command -v yay         >/dev/null 2>&1 && y=$(yay  -Qua 2>/dev/null | wc -l) || true
                command -v paru        >/dev/null 2>&1 && r=$(paru -Qua 2>/dev/null | wc -l) || true
                echo $((p+f+y+r))
            `]
            running: true
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: {
                    const n = parseInt(data)
                    root.updateCount = isNaN(n) ? 0 : n
                }
            }
            // if it fails, set 0 so we still show something
            onExited: (code) => { if (root.updateCount < 0) root.updateCount = 0 }
        }
    }

    Loader { id: updatesLoader; active: false; sourceComponent: updatesComponent }

    Timer {
        interval: 5 * 60 * 1000; running: true; repeat: true
        onTriggered: root.refreshUpdateCount()
    }
    Component.onCompleted: root.refreshUpdateCount()

    IpcHandler {
        target: "sidebarRight"

        function toggle(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            if(GlobalStates.sidebarRightOpen) Notifications.timeoutAll();
        }

        function close(): void {
            GlobalStates.sidebarRightOpen = false;
        }

        function open(): void {
            GlobalStates.sidebarRightOpen = true;
            Notifications.timeoutAll();
        }
    }

    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            if(GlobalStates.sidebarRightOpen) Notifications.timeoutAll();
        }
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = true;
            Notifications.timeoutAll();
        }
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = false;
        }
    }

}
