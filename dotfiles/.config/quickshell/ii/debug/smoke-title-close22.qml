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
    title: "smoke-title-close22"
    color: Appearance.m3colors.m3background

    StyledText {
        anchors.centerIn: parent
        renderType: Text.QtRendering
        text: "close"
        font.hintingPreference: Font.PreferNoHinting
        font.family: "Google Sans Flex"
        font.pixelSize: 22
        font.weight: Font.DemiBold
    }
}
