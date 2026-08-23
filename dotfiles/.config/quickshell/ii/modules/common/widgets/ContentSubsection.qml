import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title: ""
    property string tooltip: ""
    override default property alias contentChildren: sectionContent.children

    Layout.fillWidth: true
    Layout.topMargin: 6
    spacing: 6

    RowLayout {
        ContentSubsectionLabel {
            visible: root.title && root.title.length > 0
            text: root.title
        }
        MaterialSymbol {
            visible: root.tooltip && root.tooltip.length > 0
            text: "info"
            iconSize: Appearance.font.pixelSize.normal
            
            color: Appearance.colors.colSubtext
            MouseArea {
                id: infoMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.WhatsThisCursor
                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: infoMouseArea.containsMouse
                    text: root.tooltip
                }
            }
        }
        Item { Layout.fillWidth: true }
    }
    ColumnLayout {
        id: sectionContent
        Layout.fillWidth: true
        spacing: 6
    }
}
