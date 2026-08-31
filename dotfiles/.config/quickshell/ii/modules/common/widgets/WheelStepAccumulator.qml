import QtQuick

QtObject {
    id: root

    property real angleRemainder: 0
    property real stepSize: 120
    property int resetInterval: 250

    function takeSteps(angleDelta) {
        const delta = Number(angleDelta);
        if (!isFinite(delta) || delta === 0 || root.stepSize <= 0)
            return 0;

        // Do not combine the tail of one direction with a reversal.
        if (root.angleRemainder !== 0 && Math.sign(root.angleRemainder) !== Math.sign(delta))
            root.angleRemainder = 0;

        root.angleRemainder += delta;
        const quotient = root.angleRemainder / root.stepSize;
        const steps = quotient < 0 ? Math.ceil(quotient) : Math.floor(quotient);
        root.angleRemainder -= steps * root.stepSize;
        resetTimer.restart();
        return steps;
    }

    property Timer resetTimer: Timer {
        interval: root.resetInterval
        repeat: false
        onTriggered: root.angleRemainder = 0
    }
}
