//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env II_STANDALONE_APP=1
//@ pragma Env II_SETTINGS_APP=1

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    visible: true
    width: 960
    height: 720
    title: "page-smoke"
    color: Appearance.m3colors.m3background

    StandaloneComponentHost {
        anchors.fill: parent
        active: Config.ready
        source: Quickshell.env("II_PAGE_SOURCE")
            ? Quickshell.shellPath(Quickshell.env("II_PAGE_SOURCE"))
            : ""
    }
}
