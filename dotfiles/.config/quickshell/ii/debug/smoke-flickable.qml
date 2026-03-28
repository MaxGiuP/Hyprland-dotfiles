//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

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
    title: Translation.tr("smoke-flickable")
    color: Appearance.m3colors.m3background

    StyledFlickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight

        Column {
            id: column
            width: parent.width

            Repeater {
                model: 20

                delegate: RippleButton {
                    required property int index
                    width: parent.width
                    height: 48
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"

                    contentItem: Item {
                        anchors.fill: parent

                        MaterialSymbol {
                            id: icon
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: index % 2 === 0 ? "home" : "volume_up"
                            iconSize: 22
                        }

                        StyledText {
                            anchors.left: icon.right
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: `${Translation.tr("Row")} ${index + 1}`
                        }
                    }
                }
            }
        }
    }
}
