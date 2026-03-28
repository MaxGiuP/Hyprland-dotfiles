//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env II_STANDALONE_APP=1

import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    visible: true
    width: 480
    height: 320
    title: "smoke-ripple-loader"
    color: Appearance.m3colors.m3background

    RippleButton {
        anchors.centerIn: parent
        implicitWidth: 220
        implicitHeight: 48
        buttonRadius: Appearance.rounding.full

        contentItem: Item {
            implicitWidth: contentLoader.item?.implicitWidth ?? 0
            implicitHeight: contentLoader.item?.implicitHeight ?? 0

            Loader {
                id: contentLoader
                anchors.centerIn: parent

                sourceComponent: StyledText {
                    text: "Apply"
                    useDefaultVariableAxes: false
                }
            }
        }
    }
}
