import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Io    // Process, SplitParser

Item {
    id: root
    property bool borderless: Config.options.bar.borderless

    // shared update count
    property int updateCount: -1
    property string countFile: ""

    // no more single-writer election; any instance can write with a lock
    function refreshUpdateCount() {
        updatesLoader.active = false
        updatesLoader.active = true
    }

    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 2
    implicitHeight: rowLayout.implicitHeight

    RowLayout {
        id: rowLayout
        spacing: 4
        anchors.centerIn: parent

        // --- Update launcher with counter badge + inline tooltip
        Loader {
            active: Config.options.bar.utilButtons.showUpdates
            visible: Config.options.bar.utilButtons.showUpdates
            sourceComponent: Item {
                id: updateButtonWrap
                width: btn.implicitWidth
                height: btn.implicitHeight

                HoverHandler { id: hh }

                CircleUtilButton {
                    id: btn
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        const t = "QSUpdate";
                        const s = "/home/linmax/.config/hypr/custom/scripts/update.sh";
                        Quickshell.execDetached([
                            "hyprctl", "dispatch", "exec",
                            `/usr/bin/kitty -T ${t} ${s}`
                        ]);
                        updateWatcher.title = t;
                        updateWatcher.seenOnce = false;
                        updatePoll.running = true;
                    }
                    MaterialSymbol {
                        horizontalAlignment: Qt.AlignHCenter
                        fill: 1
                        text: "update"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer2
                    }
                }

                Rectangle {
                    id: badge
                    visible: root.updateCount > 0
                    radius: height / 2
                    color: Appearance.colors.colAccent
                    border.width: 1
                    border.color: Appearance.colors.colLayer2
                    anchors.right: btn.right
                    anchors.top: btn.top
                    anchors.rightMargin: -2
                    anchors.topMargin: -2
                    height: 16
                    implicitWidth: txt.implicitWidth + 8
                    implicitHeight: 16

                    Text {
                        id: txt
                        text: root.updateCount > 99 ? "99+" : String(root.updateCount)
                        font.pixelSize: 11
                        color: Appearance.colors.colOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                    }
                }

                Item {
                    parent: Overlay.overlay
                    visible: hh.hovered
                    z: 999
                    x: btn.mapToItem(Overlay.overlay, btn.width / 2, 0).x - tip.implicitWidth / 2
                    y: btn.mapToItem(Overlay.overlay, 0, btn.height).y
                    Rectangle {
                        id: tip
                        radius: 6
                        y: 30
                        x: -55
                        color: Appearance.colors.colLayer2
                        border.width: 1
                        border.color: Appearance.colors.colLayer2Border
                        implicitWidth: tipText.implicitWidth + 12
                        implicitHeight: tipText.implicitHeight + 8
                    }
                }
            }
        }

        // --- other util buttons (unchanged) ---
        Loader {
            active: Config.options.bar.utilButtons.showScreenSnip
            visible: Config.options.bar.utilButtons.showScreenSnip
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("screenshot.qml")])
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 1
                    text: "screenshot_region"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
        Loader {
            active: Config.options.bar.utilButtons.showColorPicker
            visible: Config.options.bar.utilButtons.showColorPicker
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: Quickshell.execDetached(["hyprpicker", "-a"])
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 1
                    text: "colorize"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
        Loader {
            active: Config.options.bar.utilButtons.showKeyboardToggle
            visible: Config.options.bar.utilButtons.showKeyboardToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: GlobalStates?.oskOpen !== undefined ? (GlobalStates.oskOpen = !GlobalStates.oskOpen) : null
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: "keyboard"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
        Loader {
            active: Config.options.bar.utilButtons.showMicToggle
            visible: Config.options.bar.utilButtons.showMicToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_SOURCE@", "toggle"])
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: Pipewire.defaultAudioSource?.audio?.muted ? "mic_off" : "mic"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
        Loader {
            active: Config.options.bar.utilButtons.showDarkModeToggle
            visible: Config.options.bar.utilButtons.showDarkModeToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: event => {
                    if (Appearance.m3colors.darkmode) {
                        Hyprland.dispatch(`exec ${Directories.wallpaperSwitchScriptPath} --mode light --noswitch`)
                    } else {
                        Hyprland.dispatch(`exec ${Directories.wallpaperSwitchScriptPath} --mode dark --noswitch`)
                    }
                }
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: Appearance.m3colors.darkmode ? "light_mode" : "dark_mode"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
        Loader {
            active: Config.options.bar.utilButtons.showPerformanceProfileToggle
            visible: Config.options.bar.utilButtons.showPerformanceProfileToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: event => {
                    if (PowerProfiles.hasPerformanceProfile) {
                        switch(PowerProfiles.profile) {
                            case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced; break;
                            case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance; break;
                            case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver; break;
                        }
                    } else {
                        PowerProfiles.profile = PowerProfiles.profile == PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced
                    }
                }
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: switch(PowerProfiles.profile) {
                        case PowerProfile.PowerSaver: return "battery_saver"
                        case PowerProfile.Balanced: return "dynamic_form"
                        case PowerProfile.Performance: return "speed"
                    }
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }

    // watcher state
    Item { id: updateWatcher; property string title: "QSUpdate"; property bool seenOnce: false }

    Timer {
        id: updatePoll
        interval: 300
        repeat: true
        running: false
        onTriggered: {
            if (!hyprClients.running) {
                hyprClients.buf = ""
                hyprClients.running = true
            }
        }
    }

    Process {
        id: hyprClients
        command: ["hyprctl", "-j", "clients"]
        property string buf: ""
        stdout: SplitParser { onRead: data => hyprClients.buf += data }
        onExited: {
            const txt = hyprClients.buf; hyprClients.buf = ""
            const found = txt.indexOf(`"title": "${updateWatcher.title}"`) !== -1
            if (!updateWatcher.seenOnce) {
                if (found) updateWatcher.seenOnce = true
            } else if (!found) {
                updatePoll.running = false
                root.refreshUpdateCount()
            }
        }
    }

    // compute total updates and write to shared file using a lock
    Component {
        id: updatesComponent
        Process {
            // flock-based writer: any instance may run this safely
            command: ["/bin/bash", "-lc", `
                set -e
                uid=$(id -u)
                rund="/run/user/$uid"
                mkdir -p "$rund"
                file="$rund/qs_upd_count"
                lock="$rund/qs_upd_count.lock"
                tmp="$rund/qs_upd_count.$$"

                exec 9>"$lock"
                if ! flock -n 9; then
                  if [ -f "$file" ]; then cat "$file"; else echo -1; fi
                  exit 0
                fi

                p=0; f=0; y=0; r=0
                command -v checkupdates >/dev/null 2>&1 && p=$(checkupdates 2>/dev/null | wc -l) || true
                command -v flatpak     >/dev/null 2>&1 && f=$(flatpak remote-ls --updates 2>/dev/null | wc -l) || true
                command -v yay         >/dev/null 2>&1 && y=$(yay  -Qua 2>/dev/null | wc -l) || true
                command -v paru        >/dev/null 2>&1 && r=$(paru -Qua 2>/dev/null | wc -l) || true

                n=$((p+f+y+r))
                printf "%s\n" "$n" > "$tmp" && mv -f "$tmp" "$file"
                echo "$n"
            `]
            running: true
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: {
                    const n = parseInt(data)
                    root.updateCount = isNaN(n) ? 0 : n
                }
            }
            onExited: (code) => { if (root.updateCount < 0) root.updateCount = 0 }
        }
    }

    Loader { id: updatesLoader; active: false; sourceComponent: updatesComponent }

    // periodic recompute on all instances; lock prevents conflicts
    Timer {
        id: recomputeTimer
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refreshUpdateCount()
    }

    // all instances read the shared file every 5 s
    Timer {
        id: syncTimer
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            if (!readCount.running) readCount.running = true
        }
    }

    Process {
        id: readCount
        command: ["/bin/bash", "-lc", `
            uid=$(id -u)
            f="/run/user/$uid/qs_upd_count"
            if [ -f "$f" ]; then cat "$f"; else echo -1; fi
        `]
        property string buf: ""
        stdout: SplitParser { splitMarker: "\n"; onRead: data => readCount.buf = data }
        onExited: {
            const n = parseInt(readCount.buf.trim())
            if (!isNaN(n) && n >= 0 && n !== root.updateCount)
                root.updateCount = n
            readCount.buf = ""
        }
    }

    Process {
        id: initCountPath
        command: ["/bin/bash", "-lc", `echo "/run/user/$(id -u)/qs_upd_count"`]
        stdout: SplitParser { splitMarker: "\n"; onRead: data => root.countFile = data }
        onExited: {
            if (!readCount.running) readCount.running = true
        }
        running: true
    }

    Component.onCompleted: {
        root.refreshUpdateCount()
    }
}
