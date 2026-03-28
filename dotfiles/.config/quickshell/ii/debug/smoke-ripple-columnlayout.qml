//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env II_STANDALONE_APP=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    visible: true
    width: 480
    height: 320
    title: "smoke-ripple-columnlayout"
    color: Appearance.m3colors.m3background

    RippleButton {
        anchors.centerIn: parent
        implicitWidth: 160
        implicitHeight: 64
        buttonRadius: Appearance.rounding.normal

        contentItem: ColumnLayout {
            anchors.centerIn: parent
            spacing: 2

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 22
                text: "light_mode"
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: "Light"
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}
