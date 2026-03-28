//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import QtQuick.Controls

ApplicationWindow {
    visible: true
    width: 480
    height: 320
    title: "smoke-basic"

    Rectangle {
        anchors.fill: parent
        color: "#202020"

        Text {
            anchors.centerIn: parent
            color: "white"
            text: "basic"
        }
    }
}
