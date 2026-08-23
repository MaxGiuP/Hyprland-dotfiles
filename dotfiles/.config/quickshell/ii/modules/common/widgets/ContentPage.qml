import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    property real baseWidth: 600
    property bool forceWidth: false
    property real horizontalContentPadding: 24
    property real bottomContentPadding: 64

    override default property alias contentChildren: contentColumn.data

    clip: true
    contentWidth: width
    contentHeight: contentColumn.implicitHeight + root.bottomContentPadding
    implicitWidth: root.baseWidth
    
    ColumnLayout {
        id: contentColumn
        width: Math.max(1, Math.min(
            root.width - root.horizontalContentPadding * 2,
            root.forceWidth ? root.baseWidth : Math.max(root.baseWidth, implicitWidth)
        ))
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: 24
        }
        spacing: 28
    }

}
