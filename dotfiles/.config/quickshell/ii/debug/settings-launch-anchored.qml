//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env II_SETTINGS_APP=1
//@ pragma Env II_STANDALONE_APP=1

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    id: root
    visible: true
    width: 1100
    height: 750
    color: Appearance.m3colors.m3background
    title: "settings-launch-anchored"

    Item {
        anchors.fill: parent
        anchors.margins: 8

        Item {
            id: titlebar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 44

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Settings")
                useDefaultVariableAxes: false
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.title
            }

            RippleButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                buttonRadius: Appearance.rounding.full
                implicitWidth: 35
                implicitHeight: 35
                onClicked: root.close()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 20
                }
            }
        }

        Rectangle {
            anchors.top: titlebar.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            color: Appearance.m3colors.m3surfaceContainerLow
            radius: Appearance.rounding.windowRounding - 8

            StandaloneComponentHost {
                anchors.fill: parent
                anchors.margins: 8
                active: Config.ready
                source: Quickshell.shellPath("../modules/settings/HomeConfigStandalone.qml")
            }
        }
    }
}
