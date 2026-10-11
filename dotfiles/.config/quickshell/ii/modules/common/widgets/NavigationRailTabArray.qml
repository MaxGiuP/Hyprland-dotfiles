import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property int currentIndex: 0
    property bool expanded: false
    override default property alias contentChildren: tabBarColumn.children
    implicitHeight: tabBarColumn.implicitHeight
    implicitWidth: tabBarColumn.implicitWidth
    Layout.topMargin: 25

    readonly property var tabButtons: tabBarColumn.children.filter(child => child.baseSize !== undefined)
    readonly property Item selectedButton: tabButtons[currentIndex] ?? null
    readonly property var highlightGeometry: {
        const button = selectedButton;
        if (!button) return {x: 0, y: 0, width: 0, height: 0};
        // Read layout coordinates explicitly so resize/text-scale relayout invalidates this binding.
        const layoutX = button.x;
        const layoutY = button.y;
        const position = button.mapToItem(root, 0, 0);
        const wide = root.expanded || button.expanded;
        const top = wide ? 0 : button.showCollapsedText
            ? button.highlightCollapsedTopMargin : (button.height - button.baseHighlightHeight) / 2;
        return {x: position.x, y: position.y + top,
            width: wide ? button.visualWidth : button.baseSize,
            height: wide ? button.height : button.baseHighlightHeight};
    }

    Rectangle {
        objectName: "activeTabIndicator"
        x: root.highlightGeometry.x
        y: root.highlightGeometry.y
        width: root.highlightGeometry.width
        height: root.highlightGeometry.height
        radius: Appearance.rounding.full
        color: Appearance.colors.colSecondaryContainer
        visible: root.selectedButton !== null

        Behavior on y {
            NumberAnimation {
                duration: Appearance.reduceMotion ? 0 : Appearance.animationCurves.expressiveFastSpatialDuration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
    }

    ColumnLayout {
        id: tabBarColumn
        anchors.fill: parent
        spacing: 0
    }
}
