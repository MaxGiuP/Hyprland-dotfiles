pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    required property Component lockSurface
    property alias context: lockContext

    // Keep lock surface visible until lockpad unlock animation finishes.
    property int unlockReleaseDelayMs: 1500
    property int lockBlurInDelayMs: 0
    property int lockBlurInDurationMs: 0
    property int unlockBlurOutDelayMs: 0
    property int unlockBlurOutDurationMs: 0

    property Component sessionLockSurface: WlSessionLockSurface {
        id: sessionLockSurface
        color: "transparent"
        Loader {
            id: lockSurfaceLoader
            active: GlobalStates.screenLocked
            anchors.fill: parent
            sourceComponent: root.lockSurface

            function syncCaptureScreen() {
                if (!item || !("captureScreen" in item))
                    return;

                item.captureScreen = sessionLockSurface.screen;
            }

            onLoaded: syncCaptureScreen()

            Connections {
                target: sessionLockSurface
                function onScreenChanged() {
                    lockSurfaceLoader.syncCaptureScreen();
                }
            }
        }
    }

    Process {
        id: unlockKeyringProc
        onExited: () => {
            KeyringStorage.fetchKeyringData();
        }
    }

    function unlockKeyring() {
        unlockKeyringProc.exec({
            environment: ({
                "UNLOCK_PASSWORD": lockContext.currentText
            }),
            command: ["bash", "-c", Quickshell.shellPath("scripts/keyring/unlock.sh")]
        });
    }

    function stopBlurAnimation() {
        blurDelayTimer.stop();
        blurAnim.stop();
    }

    function animateBlurTo(targetProgress, durationMs, easingType) {
        root.stopBlurAnimation();

        if (durationMs <= 0) {
            GlobalStates.screenLockBlurProgress = targetProgress;
            return;
        }

        blurAnim.from = GlobalStates.screenLockBlurProgress;
        blurAnim.to = targetProgress;
        blurAnim.duration = durationMs;
        blurAnim.easing.type = easingType;
        blurAnim.restart();
    }

    function scheduleBlurAnimation(targetProgress, delayMs, durationMs, easingType) {
        root.stopBlurAnimation();

        if (delayMs <= 0) {
            root.animateBlurTo(targetProgress, durationMs, easingType);
            return;
        }

        blurDelayTimer.pendingTarget = targetProgress;
        blurDelayTimer.pendingDuration = durationMs;
        blurDelayTimer.pendingEasingType = easingType;
        blurDelayTimer.interval = delayMs;
        blurDelayTimer.restart();
    }

    function startLockBlurIntro() {
        GlobalStates.screenLockBlurProgress = 0;
        root.scheduleBlurAnimation(1, root.lockBlurInDelayMs, root.lockBlurInDurationMs, Easing.OutCubic);
    }

    function startLockBlurOutro() {
        root.scheduleBlurAnimation(0, root.unlockBlurOutDelayMs, root.unlockBlurOutDurationMs, Easing.InCubic);
    }

    Timer {
        id: blurDelayTimer
        property real pendingTarget: 0
        property int pendingDuration: 0
        property int pendingEasingType: Easing.Linear
        repeat: false
        onTriggered: {
            root.animateBlurTo(pendingTarget, pendingDuration, pendingEasingType);
        }
    }

    NumberAnimation {
        id: blurAnim
        target: GlobalStates
        property: "screenLockBlurProgress"
    }

    LockContext {
        id: lockContext

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    GlobalStates.screenLockHideBar = false;
                    lockContext.reset();
                    lockContext.tryFingerUnlock();
                    root.startLockBlurIntro();
                } else {
                    root.stopBlurAnimation();
                    GlobalStates.screenLockBlurProgress = 0;
                    GlobalStates.screenLockHideBar = false;
                }
            }
        }

        onUnlocked: (targetAction) => {
            if (targetAction == LockContext.ActionEnum.Poweroff) {
                Session.poweroff();
                return;
            } else if (targetAction == LockContext.ActionEnum.Reboot) {
                Session.reboot();
                return;
            }

            if (Config.options.lock.security.unlockKeyring)
                root.unlockKeyring();

            root.startLockBlurOutro();
            unlockReleaseTimer.start();
        }
    }

    Timer {
        id: unlockReleaseTimer
        interval: root.unlockReleaseDelayMs
        repeat: false
        onTriggered: {
            GlobalStates.screenLocked = false;
            lockContext.reset();
            root.stopBlurAnimation();
            GlobalStates.screenLockBlurProgress = 0;
            GlobalStates.screenLockHideBar = false;
            if (lockContext.alsoInhibitIdle) {
                lockContext.alsoInhibitIdle = false;
                Idle.toggleInhibit(true);
            }
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: GlobalStates.screenLocked
        surface: root.sessionLockSurface
    }

    function lock() {
        if (GlobalStates.screenLocked)
            return;

        if (Config.options.lock.useHyprlock) {
            Quickshell.execDetached(["bash", "-c", "pidof hyprlock || hyprlock"]);
            return;
        }

        GlobalStates.screenLockBlurProgress = 0;
        GlobalStates.screenLockHideBar = false;
        GlobalStates.screenLocked = true;
    }

    IpcHandler {
        target: "lock"

        function activate(): void {
            root.lock();
        }
        function focus(): void {
            lockContext.shouldReFocus();
        }
    }

    GlobalShortcut {
        name: "lock"
        description: "Locks the screen"
        onPressed: { root.lock() }
    }

    GlobalShortcut {
        name: "lockFocus"
        description: "Re-focuses the lock screen. This is because Hyprland after waking up for whatever reason"
            + "decides to keyboard-unfocus the lock screen"
        onPressed: { lockContext.shouldReFocus(); }
    }

    function initIfReady() {
        if (!Config.ready || !Persistent.ready)
            return;

        if (Config.options.lock.launchOnStartup && Persistent.isNewHyprlandInstance) {
            root.lock();
        } else {
            KeyringStorage.fetchKeyringData();
        }
    }

    Connections {
        target: Config
        function onReadyChanged() { root.initIfReady(); }
    }

    Connections {
        target: Persistent
        function onReadyChanged() { root.initIfReady(); }
    }
}
