import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title
    property string icon: ""
    property string description: ""
    override default property alias contentChildren: sectionContent.children

    Layout.fillWidth: true
    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Rectangle {
            visible: root.icon.length > 0
            Layout.preferredWidth: visible ? 32 : 0
            Layout.preferredHeight: visible ? 32 : 0
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: 20
                color: Appearance.colors.colOnSecondaryContainer
                fill: 1
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                visible: root.description.length > 0
                Layout.fillWidth: true
                text: root.description
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
    }

    ColumnLayout {
        id: sectionContent
        Layout.fillWidth: true
        spacing: 8

    }
}
