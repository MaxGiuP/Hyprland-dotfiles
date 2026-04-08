import qs
import qs.services
import qs.services as Services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Io

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 2
    implicitHeight: rowLayout.implicitHeight

    property string updateTitle: "QSUpdate"
    property string updateScriptPath: "/home/linmax/.config/hypr/hyprland/scripts/update.sh"

    property bool barAutoHideEnabled: Config.options.bar.autoHide.enable

    function launchUpdateScript() {
        const lang = Services.Translation.languageCode
        Hyprland.dispatch(`exec [float;size 1000 750;center] /usr/bin/kitty -T ${root.updateTitle} ${root.updateScriptPath} ${lang}`)
        updateWatcher.title = root.updateTitle
        updateWatcher.seenOnce = false
        updatePoll.running = true
    }

    function toggleBarAutoHideInFile() {
        Config.options.bar.autoHide.enable = !Config.options.bar.autoHide.enable
    }

    GlobalShortcut {
        name: "barAutoHideToggle"
        description: "Toggle bar autoHide.enable in illogical-impulse config.json"
        onPressed: root.toggleBarAutoHideInFile()
    }


    RowLayout {
        id: rowLayout
        spacing: 4
        anchors.centerIn: parent

        Loader {
            active: Config.options.bar.utilButtons.showUpdates
            visible: Config.options.bar.utilButtons.showUpdates
            sourceComponent: Item {
                id: updateWrap
                clip: false
                implicitWidth: updateBtn.implicitWidth
                implicitHeight: updateBtn.implicitHeight

                CircleUtilButton {
                    id: updateBtn
                    anchors.fill: parent
                    onClicked: root.launchUpdateScript()

                    MaterialSymbol {
                        horizontalAlignment: Qt.AlignHCenter
                        fill: 1
                        text: "update"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer2
                    }
                }

                Item {
                    id: badge
                    z: 999999
                    property int displayCount: Services.Updates.count >= 0 ? Services.Updates.count : 0
                    visible: displayCount > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -5
                    anchors.topMargin: -5

                    property int badgeH: 14
                    property int badgeHorizontalPadding: 4
                    property string badgeTextValue: displayCount > 999 ? "999+" : String(displayCount)

                    width: Math.max(badgeH, badgeTextItem.implicitWidth + badgeHorizontalPadding * 2)
                    height: badgeH

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        antialiasing: true
                        color: badge.displayCount > 0 ? "#FFFFFF" : Appearance.colors.colLayer2
                    }

                    Text {
                        id: badgeTextItem
                        anchors.centerIn: parent
                        text: badge.badgeTextValue
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: badge.displayCount > 0 ? "#000000" : Appearance.colors.colOnLayer2
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showScreenSnip
            visible: Config.options.bar.utilButtons.showScreenSnip
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"])
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
            active: Config.options.bar.utilButtons.showScreenRecord
            visible: Config.options.bar.utilButtons.showScreenRecord
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: Quickshell.execDetached([Directories.recordScriptPath])
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 1
                    text: "videocam"
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
                onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color"])
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
                onClicked: GlobalStates.oskOpen = !GlobalStates.oskOpen
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
                    const Dash = "-"
                    const DD = Dash + Dash
                    if (Appearance.m3colors.darkmode) {
                        Hyprland.dispatch(`exec ${Directories.wallpaperSwitchScriptPath} ${DD}mode light ${DD}noswitch`)
                    } else {
                        Hyprland.dispatch(`exec ${Directories.wallpaperSwitchScriptPath} ${DD}mode dark ${DD}noswitch`)
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
                        switch (PowerProfiles.profile) {
                            case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced
                            break
                            case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance
                            break
                            case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver
                            break
                        }
                    } else {
                        PowerProfiles.profile = PowerProfiles.profile == PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced
                    }
                }
                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: switch(PowerProfiles.profile) {
                        case PowerProfile.PowerSaver: return "energy_savings_leaf"
                        case PowerProfile.Balanced: return "airwave"
                        case PowerProfile.Performance: return "local_fire_department"
                    }
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showKeyboardLayoutSwitcher && HyprlandXkb.layoutCodes.length > 1
            visible: active
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"])

                Item {
                    implicitWidth: layoutLabel.implicitWidth + 14
                    implicitHeight: layoutLabel.implicitHeight + 8

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Appearance.colors.colOutlineVariant
                    }

                    Text {
                        id: layoutLabel
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: HyprlandXkb.currentLayoutCode.split(':')[0].slice(0, 2).toUpperCase()
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer2

                        Behavior on text {
                            SequentialAnimation {
                                NumberAnimation { target: layoutLabel; property: "opacity"; to: 0; duration: 80 }
                                PropertyAction {}
                                NumberAnimation { target: layoutLabel; property: "opacity"; to: 1; duration: 80 }
                            }
                        }
                    }
                }
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showBarHideToggle
            visible: active
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: root.toggleBarAutoHideInFile()

                MaterialSymbol {
                    horizontalAlignment: Qt.AlignHCenter
                    fill: 0
                    text: root.barAutoHideEnabled ? "visibility_off" : "visibility"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }

    Item {
        id: updateWatcher
        property string title: "QSUpdate"
        property bool seenOnce: false
    }

    Timer {
        id: updatePoll
        interval: 750
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
        stdout: SplitParser {
            onRead: data => hyprClients.buf += data
        }
        onExited: {
            const txt = hyprClients.buf
            hyprClients.buf = ""
            const found = txt.indexOf(`"title": "${updateWatcher.title}"`) !== -1
            if (!updateWatcher.seenOnce) {
                if (found) updateWatcher.seenOnce = true
            } else if (!found) {
                updatePoll.running = false
                Services.Updates.refresh()
            }
        }
    }

    Component.onCompleted: {
        Services.Updates.refresh()
    }
}
