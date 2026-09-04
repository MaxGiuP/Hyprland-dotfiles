import QtQuick
import QMLTermWidget

Item {
    id: root

    required property QMLTermWidget terminal

    readonly property int value: terminal.scrollbarCurrentValue
    readonly property int minimum: terminal.scrollbarMinimum
    readonly property int maximum: terminal.scrollbarMaximum
    readonly property int lines: terminal.lines
    readonly property int totalLines: lines + maximum

    anchors.right: terminal.right
    height: totalLines > minimum
        ? terminal.height * (lines / (totalLines - minimum))
        : 0
    y: totalLines > 0 ? (terminal.height / totalLines) * (value - minimum) : 0
    opacity: 0

    function showScrollbar() {
        root.opacity = 1
        hideTimer.restart()
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    Connections {
        target: root.terminal
        function onScrollbarValueChanged() { root.showScrollbar() }
    }

    Timer {
        id: hideTimer
        onTriggered: root.opacity = 0
    }
}
