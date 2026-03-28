import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Loader {
    id: root
    property bool vertical: false
    property color color: Appearance.colors.colOnSurfaceVariant
    property color backgroundColor: Appearance.colors.colSecondaryContainer
    property color borderColor: Appearance.colors.colOutlineVariant
    active: HyprlandXkb.layoutCodes.length > 1
    visible: active

    function abbreviateLayoutCode(fullCode) {
        return fullCode.split(':').map(layout => {
            const baseLayout = layout.split('-')[0];
            return baseLayout.slice(0, 3).toUpperCase();
        }).join('\n');
    }

    sourceComponent: Rectangle {
        radius: Appearance.rounding.full
        color: mouseArea.containsPress
            ? Qt.darker(root.backgroundColor, 1.15)
            : mouseArea.containsMouse ? Qt.darker(root.backgroundColor, 1.07) : root.backgroundColor
        border.width: 1
        border.color: root.borderColor
        implicitWidth: root.vertical ? indicatorColumn.implicitWidth + 8 : indicatorRow.implicitWidth + 14
        implicitHeight: root.vertical ? indicatorColumn.implicitHeight + 12 : indicatorRow.implicitHeight + 8

        Behavior on color {
            ColorAnimation { duration: 100 }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    Quickshell.execDetached(["input-remapper-gtk"])
                } else {
                    Quickshell.execDetached(["hyprctl", "switchxkblayout", "input-remapper--------mechlands-m75-forwarded", "next"])
                }
            }
        }

        RowLayout {
            id: indicatorRow
            anchors.centerIn: parent
            visible: !root.vertical
            spacing: 4

            MaterialSymbol {
                text: "keyboard"
                iconSize: Appearance.font.pixelSize.normal
                color: root.color
            }

            Text {
                id: layoutCodeText
                horizontalAlignment: Text.AlignHCenter
                text: abbreviateLayoutCode(HyprlandXkb.currentLayoutCode)
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                font.family: "Google Sans, Roboto, sans-serif"
                font.letterSpacing: 0.5
                color: root.color

                Behavior on text {
                    SequentialAnimation {
                        NumberAnimation { target: layoutCodeText; property: "opacity"; to: 0; duration: 80 }
                        PropertyAction {}
                        NumberAnimation { target: layoutCodeText; property: "opacity"; to: 1; duration: 80 }
                    }
                }
            }
        }

        ColumnLayout {
            id: indicatorColumn
            anchors.centerIn: parent
            visible: root.vertical
            spacing: 1

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "keyboard"
                iconSize: Appearance.font.pixelSize.small
                color: root.color
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: abbreviateLayoutCode(HyprlandXkb.currentLayoutCode)
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.Medium
                font.family: "Google Sans, Roboto, sans-serif"
                font.letterSpacing: 0.5
                color: root.color
            }
        }
    }
}
