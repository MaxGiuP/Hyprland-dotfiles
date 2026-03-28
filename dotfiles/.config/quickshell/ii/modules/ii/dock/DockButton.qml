import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    readonly property real dockHeight: Config.options?.dock.height ?? 70
    readonly property real dockButtonHeight: Math.max(36, dockHeight - topInset - bottomInset)

    Layout.fillHeight: true
    Layout.topMargin: Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut
    implicitHeight: dockButtonHeight + topInset + bottomInset
    implicitWidth: implicitHeight - topInset - bottomInset
    buttonRadius: Appearance.rounding.normal

    background.implicitHeight: dockButtonHeight
}
