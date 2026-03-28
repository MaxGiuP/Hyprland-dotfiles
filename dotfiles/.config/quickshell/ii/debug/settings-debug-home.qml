//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env II_SETTINGS_APP=1
//@ pragma Env II_STANDALONE_APP=1

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    visible: true
    width: 900
    height: 600
    color: Appearance.m3colors.m3background
    title: "settings-debug-home"

    Rectangle {
        anchors.fill: parent
        color: Appearance.m3colors.m3background

        StandaloneComponentHost {
            anchors.fill: parent
            active: Config.ready
            source: Quickshell.shellPath("../modules/settings/HomeConfigStandalone.qml")
        }
    }
}
