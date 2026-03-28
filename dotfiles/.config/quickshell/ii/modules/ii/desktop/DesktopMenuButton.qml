import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common

Item {
    id: root

    property string text: ""
    property string iconName: ""
    property color textColor: Appearance.colors.colOnLayer1

    signal triggered()

    implicitWidth: row.implicitWidth + 24
    implicitHeight: 34
    Layout.fillWidth: true

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: hoverArea.containsMouse
            ? Qt.rgba(1, 1, 1, 0.1)
            : "transparent"
        Behavior on color { ColorAnimation { duration: 80 } }
    }

    RowLayout {
        id: row
        anchors {
            fill: parent
            leftMargin: 12
            rightMargin: 12
        }
        spacing: 8

        IconImage {
            visible: root.iconName.length > 0
            source: Quickshell.iconPath(root.iconName)
            implicitSize: 16
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: root.text
            color: root.textColor
            font.pixelSize: 13
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.triggered()
    }
}
