import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Rectangle {
    property real separatorPadding: Appearance.rounding.normal
    property real separatorThickness: 1

    Layout.topMargin: Appearance.sizes.elevationMargin + dockRow.padding + separatorPadding
    Layout.bottomMargin: Appearance.sizes.hyprlandGapsOut + dockRow.padding + separatorPadding
    Layout.fillHeight: true
    implicitWidth: separatorThickness
    radius: separatorThickness / 2
    color: ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colLayer0Base, 0.8)
}
