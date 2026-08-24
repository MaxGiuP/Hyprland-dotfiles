import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    property real padding: 5
    readonly property real floatingBarInset: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
    readonly property color backgroundColor: Appearance.m3colors.darkmode
        ? Appearance.colors.colLayer1
        : ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colOnLayer0, 0.88)
    readonly property color backgroundBorderColor: Appearance.m3colors.darkmode
        ? "transparent"
        : ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.55)
    implicitWidth: vertical ? Appearance.sizes.baseVerticalBarWidth : (gridLayout.implicitWidth + padding * 2)
    implicitHeight: vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight
    default property alias items: gridLayout.children

    Rectangle {
        id: background
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4 + root.floatingBarInset
            bottomMargin: root.vertical ? 0 : 4 + root.floatingBarInset
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        color: Config.options?.bar.borderless ? "transparent" : root.backgroundColor
        radius: Appearance.rounding.small
        border.width: (!Appearance.m3colors.darkmode && !Config.options?.bar.borderless) ? 1 : 0
        border.color: root.backgroundBorderColor
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors {
            verticalCenter: root.vertical ? undefined : parent.verticalCenter
            horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            left: root.vertical ? undefined : parent.left
            right: root.vertical ? undefined : parent.right
            top: root.vertical ? parent.top : undefined
            bottom: root.vertical ? parent.bottom : undefined
            margins: root.padding
        }
        columnSpacing: 4
        rowSpacing: 12
    }
}
