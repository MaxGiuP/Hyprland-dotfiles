//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env II_STANDALONE_APP=1
//@ pragma Env II_SETTINGS_APP=1

import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    visible: true
    width: 520
    height: 320
    title: "smoke-styled-slider"
    color: Appearance.m3colors.m3background

    StyledSlider {
        anchors.centerIn: parent
        width: 320
        from: 0
        to: 1
        value: 0.42
        configuration: StyledSlider.Configuration.M
        usePercentTooltip: false
        tooltipContent: "42%"
    }
}
