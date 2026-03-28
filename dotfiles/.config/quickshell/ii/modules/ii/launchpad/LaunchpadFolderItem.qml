import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Item {
    id: root
    property string folderName: ""
    property var apps: []
    property int cellWidth: 176
    property int iconSize: 88
    property int labelSize: 14
    readonly property int folderVisualSize: Math.max(112, Math.min(Math.round(root.cellWidth * 0.82), root.cellWidth - 16))
    readonly property int previewIconSize: Math.max(27, Math.min(34, Math.round(root.cellWidth * 0.205)))
    readonly property int iconLabelSpacing: Math.max(10, Math.round(root.folderVisualSize * 0.09))
    signal launchRequested()
    scale: folderButton.containsMouse ? 1.02 : 1.0
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    RippleButton {
        id: folderButton
        anchors.fill: parent
        anchors.margins: 12
        buttonRadius: Appearance.rounding.large
        colBackground: Qt.rgba(1, 1, 1, 0.0)
        colBackgroundHover: Qt.rgba(1, 1, 1, 0.15)
        colRipple: Qt.rgba(1, 1, 1, 0.28)

        onClicked: root.launchRequested()

        contentItem: Item {}

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 24
            spacing: root.iconLabelSpacing

            // Folder: rounded square with 2×2 icon grid
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: root.folderVisualSize
                height: root.folderVisualSize
                radius: Math.max(14, Math.round(root.folderVisualSize * 0.11))
                color: Appearance.colors.colSurfaceContainerHighest
                border.color: Appearance.colors.colLayer0Border
                border.width: 1

                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    spacing: Math.max(5, Math.round(root.folderVisualSize * 0.055))

                    Repeater {
                        model: Math.min(root.apps.length, 4)
                        delegate: IconImage {
                            required property int index
                            source: Quickshell.iconPath(root.apps[index]?.icon ?? "", "image-missing")
                            implicitSize: root.previewIconSize
                        }
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                text: root.folderName
                color: Appearance.colors.colOnLayer1
                font.pixelSize: root.labelSize
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
                maximumLineCount: 2
            }
        }
    }
}
