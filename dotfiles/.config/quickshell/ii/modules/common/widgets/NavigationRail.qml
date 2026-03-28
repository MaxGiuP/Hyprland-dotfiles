import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool expanded: true
    property int currentIndex: 0
    default property alias data: railColumn.data
    implicitWidth: railColumn.implicitWidth
    implicitHeight: railColumn.implicitHeight

    StyledFlickable {
        id: railFlickable
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: railColumn.height
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: railColumn
            width: railFlickable.width
            height: Math.max(implicitHeight, railFlickable.height)
            spacing: 5
        }
    }
}
