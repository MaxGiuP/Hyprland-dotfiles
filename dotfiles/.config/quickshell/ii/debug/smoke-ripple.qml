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
    title: Translation.tr("smoke-ripple")
    color: Appearance.m3colors.m3background

    RippleButton {
        anchors.centerIn: parent
        implicitWidth: 160
        implicitHeight: 48
        buttonRadius: Appearance.rounding.full
        buttonText: Translation.tr("Ripple")
    }
}
