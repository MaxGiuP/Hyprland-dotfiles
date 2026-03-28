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
    title: Translation.tr("smoke-title-font")
    color: Appearance.m3colors.m3background

    StyledText {
        anchors.centerIn: parent
        text: Translation.tr("Settings")
        color: Appearance.colors.colOnLayer0
        font.family: Appearance.font.family.title
        font.pixelSize: Appearance.font.pixelSize.title
        font.variableAxes: Appearance.font.variableAxes.title
    }
}
