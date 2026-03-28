//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    visible: true
    width: 480
    height: 320
    title: Translation.tr("smoke-services")
    color: Appearance.m3colors.m3background

    StyledText {
        anchors.centerIn: parent
        color: Appearance.colors.colOnLayer0
        text: Config.ready ? Translation.tr("services") : Translation.tr("loading")
    }
}
