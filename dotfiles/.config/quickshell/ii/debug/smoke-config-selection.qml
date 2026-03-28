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
    width: 700
    height: 500
    title: Translation.tr("smoke-config-selection")
    color: Appearance.m3colors.m3background

    ContentPage {
        anchors.fill: parent

        ContentSection {
            icon: "language"
            title: Translation.tr("Language")

            ConfigSelectionArray {
                currentValue: "auto"
                options: [
                    { displayName: Translation.tr("Auto"), icon: "check", value: "auto" },
                    { displayName: Translation.tr("Italian"), icon: "translate", value: "it_IT" }
                ]
            }
        }
    }
}
