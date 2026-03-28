//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env II_STANDALONE_APP=1
//@ pragma Env II_SETTINGS_APP=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    visible: true
    width: 600
    height: 300
    title: "smoke-ripplewithicon-only"
    color: Appearance.m3colors.m3background

    ContentPage {
        anchors.fill: parent

        ContentSection {
            icon: "accessibility_new"
            title: "Accessibility"

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "save"
                mainText: "Apply"
            }
        }
    }
}
