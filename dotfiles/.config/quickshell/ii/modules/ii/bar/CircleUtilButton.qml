import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

RippleButton {
    id: button

    required default property Item content
    property bool extraActiveCondition: false

    implicitHeight: Math.max(content.implicitHeight, 26, content.implicitHeight)
    implicitWidth: implicitHeight
    contentItem: content

    colBackground: Appearance.m3colors.darkmode
        ? ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        : ColorUtils.mix(Appearance.colors.colLayer1Base, Appearance.colors.colOnLayer1, 0.90)
    colBackgroundHover: Appearance.m3colors.darkmode
        ? Appearance.colors.colLayer1Hover
        : ColorUtils.mix(Appearance.colors.colLayer1Base, Appearance.colors.colOnLayer1, 0.80)

}
