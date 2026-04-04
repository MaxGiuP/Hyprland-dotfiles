import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    property real visualSize: 0
    readonly property real dockHeight: Config.options?.dock.height ?? 70
    readonly property real dockButtonHeight: Math.max(36, visualSize > 0 ? visualSize : dockHeight - topInset - bottomInset)

    Layout.fillHeight: true
    Layout.topMargin: Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut
    implicitHeight: dockButtonHeight + topInset + bottomInset
    implicitWidth: implicitHeight - topInset - bottomInset
    buttonRadius: Math.max(Appearance.rounding.small, Math.round(dockButtonHeight * 0.32))

    background.implicitHeight: dockButtonHeight
}
