pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Qt5Compat.GraphicalEffects
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

    // Blur progression: 0 = sharp, 1 = full configured blur.
    property real blurProgress: 0.0
    property real blurStrength: 0.68
    property string screenshotVersion: "0"
    property bool pendingLock: false

    Behavior on blurProgress {
        NumberAnimation {
            duration: 420
            easing.type: Easing.OutCubic
        }
    }

    property Component sessionLockSurface: WlSessionLockSurface {
        id: sessionLockSurface
        // Transparent lock surface so screenshot layer controls visuals.
        color: "transparent"

        Item {
            anchors.fill: parent

            Image {
                id: screenshotBg
                anchors.centerIn: parent
                width: parent.width * Config.options.lock.blur.extraZoom
                height: parent.height * Config.options.lock.blur.extraZoom
                fillMode: Image.PreserveAspectCrop
                cache: false
                source: GlobalStates.screenLocked
                    ? ("file:///tmp/quickshell/lock/screenshot-"
                        + (sessionLockSurface.screen?.name ?? "")
                        + ".png?v=" + root.screenshotVersion)
                    : ""
            }

            FastBlur {
                anchors.fill: parent
                source: screenshotBg
                radius: Config.options.lock.blur.enable
                    ? (Config.options.lock.blur.radius * root.blurProgress * root.blurStrength)
                    : 0
            }
        }

        Loader {
            active: GlobalStates.screenLocked
            anchors.fill: parent
            sourceComponent: root.lockSurface
        }
    }

    function captureScreens() {
        if (captureProc.running)
            return;

        captureProc.exec({
            command: ["bash", "-c",
                "mkdir -p /tmp/quickshell/lock"
                + " && for o in $(hyprctl monitors -j | jq -r '.[].name');"
                + " do grim -o \"$o\" \"/tmp/quickshell/lock/screenshot-$o.png\" &"
                + " done; wait"
            ]
        });
    }

    Process {
        id: captureProc
        onExited: () => {
            root.screenshotVersion = Date.now().toString();
            if (root.pendingLock) {
                root.pendingLock = false;
                GlobalStates.screenLocked = true;
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

    LockContext {
        id: lockContext

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    lockContext.reset();
                    lockContext.tryFingerUnlock();
                    root.blurProgress = 1.0;
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

            // Progressive unblur while lockpad unlock animation runs.
            root.blurProgress = 0.0;
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
            if (lockContext.alsoInhibitIdle) {
                lockContext.alsoInhibitIdle = false;
                Idle.toggleInhibit(true);
            }
            root.blurProgress = 0.0;
            root.pendingLock = false;
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: GlobalStates.screenLocked
        surface: root.sessionLockSurface
    }

    function lock() {
        root.blurProgress = 0.0;
        root.pendingLock = true;

        if (Config.options.lock.useHyprlock) {
            Quickshell.execDetached(["bash", "-c", "pidof hyprlock || hyprlock"]);
            return;
        }

        root.captureScreens();
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
