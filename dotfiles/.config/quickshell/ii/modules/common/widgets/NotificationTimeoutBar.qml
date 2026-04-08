import QtQuick
import Qt5Compat.GraphicalEffects

Item {
    id: root

    required property var notification
    property color fillColor: "#ffffff"
    property color trackColor: Qt.rgba(fillColor.r, fillColor.g, fillColor.b, 0.16)
    property real outerRadius: 0

    readonly property real progress: Math.max(0, Math.min(1, Number(notification?.timeoutProgress ?? 0)))

    visible: (notification?.popup ?? false) && ((notification?.timeoutDurationMs ?? 0) > 0)
    implicitHeight: 3
    layer.enabled: root.outerRadius > 0
    layer.effect: OpacityMask {
        maskSource: Item {
            width: root.width
            height: root.height
            clip: true

            Rectangle {
                width: parent.width
                height: parent.height + root.outerRadius
                y: -root.outerRadius
                radius: root.outerRadius
                color: "#ffffff"
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.trackColor
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * root.progress
        radius: height / 2
        color: root.fillColor
        opacity: (root.notification?.timeoutPaused ?? false) ? 0.7 : 1
    }
}
