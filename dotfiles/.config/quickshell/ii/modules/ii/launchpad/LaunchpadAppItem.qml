import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Item {
    id: root
    property var entry
    property bool deleteMode: false
    property bool isDragSource: false
    property int iconSize: 88
    property int labelSize: 14
    signal launchRequested()
    signal deleteModeRequested()

    opacity: root.isDragSource ? 0.0 : 1.0
    scale: root.isDragSource ? 0.94 : 1.0
    Behavior on opacity { NumberAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // Snap rotation to 0 when exiting delete mode
    onDeleteModeChanged: { if (!deleteMode) root.rotation = 0 }

    // Jiggle when in delete mode
    SequentialAnimation on rotation {
        running: root.deleteMode && !root.isDragSource
        loops: Animation.Infinite
        NumberAnimation { to: -2.5; duration: 80; easing.type: Easing.InOutSine }
        NumberAnimation { to:  2.5; duration: 80; easing.type: Easing.InOutSine }
        NumberAnimation { to:  0;   duration: 50 }
        PauseAnimation  { duration: 60 }
    }
    Behavior on rotation {
        enabled: !root.deleteMode
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    // Hover background
    Rectangle {
        anchors.fill: parent
        anchors.margins: 12
        radius: Appearance.rounding.large
        color: interactArea.containsMouse && !root.deleteMode
               ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.0)
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    // Icon + label
    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - 24
        spacing: 10

        IconImage {
            Layout.alignment: Qt.AlignHCenter
            source: Quickshell.iconPath(root.entry?.icon ?? "", "image-missing")
            implicitSize: root.iconSize
            scale: interactArea.containsMouse && !root.deleteMode ? 1.04 : 1.0
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            text: root.entry?.name ?? ""
            color: "white"
            font.pixelSize: root.labelSize
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.55)
        }
    }

    // Click to launch (when not in delete mode) / long-press to enter delete mode
    MouseArea {
        id: interactArea
        anchors.fill: parent
        anchors.margins: 12
        hoverEnabled: true
        // Only active when the cell-level drag area is not covering us (i.e. not in deleteMode)
        enabled: !root.deleteMode
        pressAndHoldInterval: 800
        onPressAndHold: root.deleteModeRequested()
        onClicked: {
            root.entry?.execute()
            root.launchRequested()
        }
    }
}
