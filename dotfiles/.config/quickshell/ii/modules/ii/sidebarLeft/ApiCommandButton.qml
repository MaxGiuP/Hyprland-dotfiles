import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

GroupButton {
    id: button
    property string buttonText

    Layout.fillWidth: false
    Layout.fillHeight: false

    horizontalPadding: 8
    verticalPadding: 6

    baseWidth: contentItem.implicitWidth + horizontalPadding * 2
    clickedWidth: baseWidth + 14
    baseHeight: contentItem.implicitHeight + verticalPadding * 2
    buttonRadius: down ? Appearance.rounding.verysmall : Appearance.rounding.small

    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.colors.colLayer2Active
    property color colText: toggled ? ColorUtils.bestTextColor(button.color) : Appearance.m3colors.m3onSurface

    contentItem: StyledText {
        horizontalAlignment: Text.AlignHCenter
        text: buttonText
        color: button.colText
    }
}
