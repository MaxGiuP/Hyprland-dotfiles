import QtQuick

Item {
    id: root

    property string text: ""
    property color textColor: "white"
    property color outlineColor: "black"
    property int pixelSize: 13
    property real extraOutlineWidth: 0.75

    implicitWidth: foregroundText.implicitWidth
    implicitHeight: foregroundText.implicitHeight

    readonly property var outlineOffsets: [
        Qt.point(-root.extraOutlineWidth, -root.extraOutlineWidth),
        Qt.point(0, -root.extraOutlineWidth),
        Qt.point(root.extraOutlineWidth, -root.extraOutlineWidth),
        Qt.point(-root.extraOutlineWidth, 0),
        Qt.point(root.extraOutlineWidth, 0),
        Qt.point(-root.extraOutlineWidth, root.extraOutlineWidth),
        Qt.point(0, root.extraOutlineWidth),
        Qt.point(root.extraOutlineWidth, root.extraOutlineWidth),
    ]

    Repeater {
        model: root.outlineOffsets

        delegate: Text {
            required property var modelData

            x: modelData.x
            y: modelData.y
            width: root.width
            text: root.text
            color: root.outlineColor
            font.pixelSize: root.pixelSize
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            style: Text.Outline
            styleColor: root.outlineColor
        }
    }

    Text {
        id: foregroundText
        z: 1
        width: root.width
        text: root.text
        color: root.textColor
        font.pixelSize: root.pixelSize
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        style: Text.Outline
        styleColor: root.outlineColor
    }
}
