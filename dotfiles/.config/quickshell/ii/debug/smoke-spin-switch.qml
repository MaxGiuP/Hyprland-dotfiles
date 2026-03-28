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
    width: 800
    height: 500
    title: "smoke-spin-switch"
    color: Appearance.m3colors.m3background

    ContentPage {
        anchors.fill: parent

        ContentSection {
            icon: "accessibility_new"
            title: "Accessibility"

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "mouse"
                    text: "Cursor size"
                    from: 16
                    to: 96
                    stepSize: 1
                    value: 24
                }

                ConfigSpinBox {
                    icon: "format_size"
                    text: "Text scaling (%)"
                    from: 50
                    to: 200
                    stepSize: 5
                    value: 100
                }
            }

            ConfigSwitch {
                buttonIcon: "animation"
                text: "Enable animations"
                checked: true
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "save"
                mainText: "Apply"
            }
        }
    }
}
