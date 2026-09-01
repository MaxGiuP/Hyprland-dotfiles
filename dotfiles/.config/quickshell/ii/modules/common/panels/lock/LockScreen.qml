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
    property var loadedLockSurface: null
    property bool lockContentActive: false
    property bool sessionLockActive: false
    property bool releaseInProgress: false

    // Keep lock surface visible until lockpad unlock animation finishes.
    property int unlockReleaseDelayMs: 1500
    property int lockBlurInDelayMs: 0
    property int lockBlurInDurationMs: 0
    property int unlockBlurOutDelayMs: 0
    property int unlockBlurOutDurationMs: 0
    property int unlockSurfaceDetachDelayMs: 250
    // Keep the QML contents alive briefly after releasing ext-session-lock.
    // Destroying the lock surface in the same frame can make Hyprland reject
    // the client with an "Invalid size" protocol error on unlock.
    property int unlockUiRestoreDelayMs: 500

    property Component sessionLockSurface: WlSessionLockSurface {
        id: sessionLockSurface
        color: "transparent"
        Loader {
            id: lockSurfaceLoader
            active: root.lockContentActive
            anchors.fill: parent
            sourceComponent: root.lockSurface

            function syncCaptureScreen() {
                if (!item || !("captureScreen" in item))
                    return;

                if (("releasePrepared" in item) && item.releasePrepared)
                    return;

                item.captureScreen = sessionLockSurface.screen;
            }

            function prepareForRelease(immediate) {
                if (item && ("prepareForRelease" in item))
                    item.prepareForRelease(!!immediate);
            }

            function suspendScreenCapture() {
                if (item && ("suspendScreenCapture" in item))
                    item.suspendScreenCapture();
            }

            function resumeScreenCapture() {
                if (item && ("resumeScreenCapture" in item))
                    item.resumeScreenCapture();
            }

            onLoaded: {
                root.loadedLockSurface = item;
                syncCaptureScreen();
            }
            onActiveChanged: {
                if (!active)
                    root.loadedLockSurface = null;
            }

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

    function prepareLockSurfaceForRelease(immediate) {
        if (root.loadedLockSurface && ("prepareForRelease" in root.loadedLockSurface))
            root.loadedLockSurface.prepareForRelease(!!immediate);
    }

    function logLockRelease(stage) {
        console.info(`[LockScreen] ${stage} screenLocked=${GlobalStates.screenLocked} sessionActive=${root.sessionLockActive} contentActive=${root.lockContentActive}`);
    }

    function finishReleaseLock() {
        root.logLockRelease("unlock-state-finish");
        unlockReleaseTimer.stop();
        unlockSurfaceDetachTimer.stop();
        unlockUiRestoreTimer.stop();
        const alsoInhibitIdle = lockContext.alsoInhibitIdle;
        root.prepareLockSurfaceForRelease(true);
        root.releaseInProgress = false;
        GlobalStates.screenLocked = false;
        root.lockContentActive = false;
        root.sessionLockActive = false;
        lockContext.reset();
        root.stopBlurAnimation();
        GlobalStates.screenLockBlurProgress = 0;
        GlobalStates.screenLockHideBar = false;
        if (alsoInhibitIdle) {
            lockContext.alsoInhibitIdle = false;
            Idle.toggleInhibit(true);
        }
    }

    function releaseSessionLock() {
        root.logLockRelease("session-release");
        root.prepareLockSurfaceForRelease(true);
        root.sessionLockActive = false;
        if (root.unlockUiRestoreDelayMs <= 0)
            Qt.callLater(root.finishReleaseLock);
        else
            unlockUiRestoreTimer.restart();
    }

    function completeReleaseLock() {
        root.logLockRelease("complete-release");
        root.releaseInProgress = true;
        root.prepareLockSurfaceForRelease(false);
        if (root.unlockSurfaceDetachDelayMs <= 0)
            Qt.callLater(root.releaseSessionLock);
        else
            unlockSurfaceDetachTimer.restart();
    }

    function releaseLock() {
        root.logLockRelease("release-request");
        if (root.releaseInProgress)
            return;

        root.completeReleaseLock();
    }

    Timer {
        id: unlockSurfaceDetachTimer
        interval: root.unlockSurfaceDetachDelayMs
        repeat: false
        onTriggered: root.releaseSessionLock()
    }

    Timer {
        id: unlockUiRestoreTimer
        interval: root.unlockUiRestoreDelayMs
        repeat: false
        onTriggered: root.finishReleaseLock()
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
                    root.releaseInProgress = false;
                    root.lockContentActive = true;
                    root.sessionLockActive = true;
                    unlockSurfaceDetachTimer.stop();
                    unlockUiRestoreTimer.stop();
                    unlockReleaseTimer.stop();
                    GlobalStates.screenLockHideBar = false;
                    lockContext.reset();
                    lockContext.tryFingerUnlock();
                    root.startLockBlurIntro();
                } else {
                    root.releaseInProgress = false;
                    root.lockContentActive = false;
                    root.sessionLockActive = false;
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
            if (root.unlockReleaseDelayMs <= 0)
                root.releaseLock();
            else
                unlockReleaseTimer.start();
        }
    }

    Timer {
        id: unlockReleaseTimer
        interval: root.unlockReleaseDelayMs
        repeat: false
        onTriggered: root.releaseLock()
    }

    WlSessionLock {
        id: sessionLock
        locked: root.sessionLockActive
        surface: root.sessionLockSurface
    }

    Component.onCompleted: {
        if (GlobalStates.screenLocked) {
            root.lockContentActive = true;
            root.sessionLockActive = true;
        }
    }

    function lock() {
        if (GlobalStates.screenLocked)
            return;

        // A deliberate lock ends any temporary coffee-mode request. This lets
        // the locked machine continue through display-off and suspend even if
        // Keep awake had been enabled earlier.
        Idle.toggleInhibit(false);

        if (Config.options.lock.useHyprlock) {
            Quickshell.execDetached(["bash", "-c", "pidof hyprlock || hyprlock"]);
            return;
        }

        GlobalStates.screenLockBlurProgress = 0;
        GlobalStates.screenLockHideBar = false;
        unlockSurfaceDetachTimer.stop();
        unlockUiRestoreTimer.stop();
        unlockReleaseTimer.stop();
        root.lockContentActive = true;
        root.sessionLockActive = true;
        root.releaseInProgress = false;
        GlobalStates.screenLocked = true;
    }

    IpcHandler {
        target: "lock"
        readonly property bool locked: GlobalStates.screenLocked
            || root.sessionLockActive
            || root.releaseInProgress

        function status() {
            return locked ? "locked" : "unlocked";
        }

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
