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

        // A compositor may amplify a normal wheel event beyond 120. It is
        // still one physical notch, so discrete controls must act only once.
        if (Math.abs(delta) >= root.stepSize) {
            root.angleRemainder = 0;
            resetTimer.stop();
            return delta < 0 ? -1 : 1;
        }

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
