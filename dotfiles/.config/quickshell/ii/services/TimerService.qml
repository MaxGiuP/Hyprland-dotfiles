pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Simple Pomodoro time manager.
 */
Singleton {
    id: root

    property bool countdownRunning: Persistent.states.timer.countdown.running
    property int countdownDuration: Persistent.states.timer.countdown.duration
    property int countdownSecondsLeft: countdownDuration

    property int focusTime: Config.options.time.pomodoro.focus
    property int breakTime: Config.options.time.pomodoro.breakTime
    property int longBreakTime: Config.options.time.pomodoro.longBreak
    property int cyclesBeforeLongBreak: Config.options.time.pomodoro.cyclesBeforeLongBreak

    property bool pomodoroRunning: Persistent.states.timer.pomodoro.running
    property bool pomodoroBreak: Persistent.states.timer.pomodoro.isBreak
    property bool pomodoroLongBreak: Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak);
    property int pomodoroLapDuration: pomodoroLongBreak ? longBreakTime : pomodoroBreak ? breakTime : focusTime // This is a binding that's to be kept
    property int pomodoroSecondsLeft: pomodoroLapDuration // Reasonable init value, to be changed
    property int pomodoroCycle: Persistent.states.timer.pomodoro.cycle

    property bool stopwatchRunning: Persistent.states.timer.stopwatch.running
    property int stopwatchTime: 0
    property int stopwatchStart: Persistent.states.timer.stopwatch.start
    property var stopwatchLaps: Persistent.states.timer.stopwatch.laps
    property bool initialized: false

    // General
    Component.onCompleted: {
        root.initializeFromState();
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready)
                root.initializeFromState();
        }
    }

    function getCurrentTimeInSeconds() {  // Pomodoro uses Seconds
        return Math.floor(Date.now() / 1000);
    }

    function getCurrentTimeIn10ms() {  // Stopwatch uses 10ms
        return Math.floor(Date.now() / 10);
    }

    function normalizePositiveInt(value, fallbackValue) {
        const parsed = parseInt(value);
        if (!isNaN(parsed) && parsed > 0) return parsed;
        return fallbackValue;
    }

    function initializeFromState() {
        if (!Persistent.ready) return;

        const nowSeconds = getCurrentTimeInSeconds();
        const countdownDuration = normalizePositiveInt(Persistent.states.timer.countdown.duration, 300);
        Persistent.states.timer.countdown.duration = countdownDuration;
        if (Persistent.states.timer.countdown.start <= 0)
            Persistent.states.timer.countdown.start = nowSeconds;

        const pomodoroCycle = Math.max(0, parseInt(Persistent.states.timer.pomodoro.cycle) || 0);
        Persistent.states.timer.pomodoro.cycle = pomodoroCycle;
        if (Persistent.states.timer.pomodoro.start <= 0)
            Persistent.states.timer.pomodoro.start = nowSeconds;

        if (!stopwatchRunning)
            stopwatchReset();
        else
            refreshStopwatch();

        refreshCountdown();
        refreshPomodoro();
        initialized = true;
    }

    // Countdown
    function refreshCountdown() {
        if (!Persistent.ready) return;

        const nowSeconds = getCurrentTimeInSeconds();
        const duration = Math.max(1, Persistent.states.timer.countdown.duration || 300);
        let start = normalizePositiveInt(Persistent.states.timer.countdown.start, nowSeconds);
        let elapsed = nowSeconds - start;

        if (!countdownRunning) {
            if (elapsed < 0 || elapsed > duration) {
                Persistent.states.timer.countdown.start = nowSeconds;
                countdownSecondsLeft = duration;
            } else {
                countdownSecondsLeft = Math.max(0, duration - elapsed);
            }
            return;
        }

        if (countdownRunning && elapsed >= duration) {
            Persistent.states.timer.countdown.running = false;
            countdownSecondsLeft = 0;
            Quickshell.execDetached(["notify-send", Translation.tr("Timer"), Translation.tr("Countdown finished"), "-a", "Shell"]);
            if (Config.options.sounds.pomodoro) {
                Audio.playSystemSound("alarm-clock-elapsed")
            }
            return;
        }

        countdownSecondsLeft = Math.max(0, duration - elapsed);
    }

    Timer {
        id: countdownTimer
        interval: 200
        running: root.countdownRunning
        repeat: true
        onTriggered: refreshCountdown()
    }

    function setCountdownDuration(seconds) {
        Persistent.states.timer.countdown.duration = Math.max(1, parseInt(seconds) || 300);
        Persistent.states.timer.countdown.start = getCurrentTimeInSeconds();
        countdownSecondsLeft = Persistent.states.timer.countdown.duration;
        if (!countdownRunning) {
            refreshCountdown();
        }
    }

    function toggleCountdown() {
        const duration = Math.max(1, Persistent.states.timer.countdown.duration || 300);
        const remaining = countdownSecondsLeft > 0 ? countdownSecondsLeft : duration;

        Persistent.states.timer.countdown.running = !countdownRunning;
        if (Persistent.states.timer.countdown.running) {
            Persistent.states.timer.countdown.start = getCurrentTimeInSeconds() + remaining - duration;
            refreshCountdown();
        }
    }

    function resetCountdown() {
        Persistent.states.timer.countdown.running = false;
        Persistent.states.timer.countdown.start = getCurrentTimeInSeconds();
        countdownSecondsLeft = Math.max(1, Persistent.states.timer.countdown.duration || 300);
        refreshCountdown();
    }

    // Pomodoro
    function refreshPomodoro() {
        if (!Persistent.ready) return;

        const nowSeconds = getCurrentTimeInSeconds();
        const lapDuration = Math.max(1, pomodoroLapDuration);
        let start = normalizePositiveInt(Persistent.states.timer.pomodoro.start, nowSeconds);
        let elapsed = nowSeconds - start;

        if (!pomodoroRunning) {
            if (elapsed < 0 || elapsed > lapDuration) {
                Persistent.states.timer.pomodoro.start = nowSeconds;
                pomodoroSecondsLeft = lapDuration;
            } else {
                pomodoroSecondsLeft = Math.max(0, lapDuration - elapsed);
            }
            return;
        }

        // Work <-> break ?
        if (nowSeconds >= start + lapDuration) {
            // Reset counts
            Persistent.states.timer.pomodoro.isBreak = !Persistent.states.timer.pomodoro.isBreak;
            Persistent.states.timer.pomodoro.start = nowSeconds;

            // Send notification
            let notificationMessage;
            if (Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak)) {
                notificationMessage = Translation.tr(`🌿 Long break: %1 minutes`).arg(Math.floor(longBreakTime / 60));
            } else if (Persistent.states.timer.pomodoro.isBreak) {
                notificationMessage = Translation.tr(`☕ Break: %1 minutes`).arg(Math.floor(breakTime / 60));
            } else {
                notificationMessage = Translation.tr(`🔴 Focus: %1 minutes`).arg(Math.floor(focusTime / 60));
            }

            Quickshell.execDetached(["notify-send", "Pomodoro", notificationMessage, "-a", "Shell"]);
            if (Config.options.sounds.pomodoro) {
                Audio.playSystemSound("alarm-clock-elapsed")
            }

            if (!pomodoroBreak) {
                Persistent.states.timer.pomodoro.cycle = (Persistent.states.timer.pomodoro.cycle + 1) % root.cyclesBeforeLongBreak;
            }

            start = Persistent.states.timer.pomodoro.start;
            elapsed = 0;
        }

        pomodoroSecondsLeft = Math.max(0, lapDuration - elapsed);
    }

    Timer {
        id: pomodoroTimer
        interval: 200
        running: root.pomodoroRunning
        repeat: true
        onTriggered: refreshPomodoro()
    }

    function togglePomodoro() {
        Persistent.states.timer.pomodoro.running = !pomodoroRunning;
        if (Persistent.states.timer.pomodoro.running) {
            // Start/Resume
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds() + pomodoroSecondsLeft - pomodoroLapDuration;
        }
    }

    function resetPomodoro() {
        Persistent.states.timer.pomodoro.running = false;
        Persistent.states.timer.pomodoro.isBreak = false;
        Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
        Persistent.states.timer.pomodoro.cycle = 0;
        refreshPomodoro();
    }

    // Stopwatch
    function refreshStopwatch() {  // Stopwatch stores time in 10ms
        stopwatchTime = getCurrentTimeIn10ms() - stopwatchStart;
    }

    Timer {
        id: stopwatchTimer
        interval: 10
        running: root.stopwatchRunning
        repeat: true
        onTriggered: refreshStopwatch()
    }

    function toggleStopwatch() {
        if (root.stopwatchRunning)
            stopwatchPause();
        else
            stopwatchResume();
    }

    function stopwatchPause() {
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchResume() {
        if (stopwatchTime === 0) Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = true;
        Persistent.states.timer.stopwatch.start = getCurrentTimeIn10ms() - stopwatchTime;
    }

    function stopwatchReset() {
        stopwatchTime = 0;
        Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchRecordLap() {
        Persistent.states.timer.stopwatch.laps.push(stopwatchTime);
    }
}
