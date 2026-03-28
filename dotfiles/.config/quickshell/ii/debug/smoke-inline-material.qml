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
    title: Translation.tr("smoke-inline-material")
    color: Appearance.m3colors.m3background

    StyledText {
        property real iconPxSize: 48
        property real fill: 0
        anchors.centerIn: parent
        renderType: Text.QtRendering
        text: "close"
        font.hintingPreference: Font.PreferNoHinting
        font.family: Appearance?.font.family.main ?? "Sans Serif"
        font.pixelSize: iconPxSize
        font.weight: fill >= 0.5 ? Font.DemiBold : Font.Normal
    }
}
