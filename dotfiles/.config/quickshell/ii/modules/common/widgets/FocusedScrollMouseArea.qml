import QtQuick

MouseArea { // Right side | scroll to change volume
    id: root

    signal scrollUp(delta: int)
    signal scrollDown(delta: int)
    signal scrollClick()
    signal movedAway()

    property bool hovered: false
    property real lastScrollX: 0
    property real lastScrollY: 0
    property bool trackingScroll: false
    property real moveThreshold: 20

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true

    WheelStepAccumulator {
        id: wheelSteps
    }

    onEntered: {
        root.hovered = true
    }

    onExited: {
        root.hovered = false
        root.trackingScroll = false
    }

    onWheel: event => {
        const steps = wheelSteps.takeSteps(event.angleDelta.y);
        for (let index = 0; index < Math.abs(steps); ++index) {
            if (steps < 0)
                root.scrollDown(-wheelSteps.stepSize);
            else
                root.scrollUp(wheelSteps.stepSize);
        }

        root.lastScrollX = event.x
        root.lastScrollY = event.y
        root.trackingScroll = true
    }

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) {
            root.scrollClick()
        }
    }

    onPositionChanged: mouse => {
        if (root.trackingScroll) {
            const dx = mouse.x - root.lastScrollX
            const dy = mouse.y - root.lastScrollY
            if (Math.sqrt(dx * dx + dy * dy) > root.moveThreshold) {
                root.movedAway()
                root.trackingScroll = false
            }
        }
    }

    onContainsMouseChanged: {
        if (!root.containsMouse && root.trackingScroll) {
            root.movedAway()
            root.trackingScroll = false
        }
    }
}
