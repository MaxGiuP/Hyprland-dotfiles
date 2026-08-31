pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string currentMode: "balanced"
    property bool captured: false
    property bool previousBarAutoHide: false
    property bool previousDockEnabled: false
    property bool previousSilent: false
    property bool previousIdleInhibit: false
    property string previousPowerProfile: "balanced"
    readonly property var modes: [
        { id: "balanced", name: "Balanced", icon: "tune", detail: "Restore your normal desktop" },
        { id: "focus", name: "Focus", icon: "center_focus_strong", detail: "Quiet alerts and hide chrome" },
        { id: "gaming", name: "Gaming", icon: "sports_esports", detail: "Performance power and no interruptions" },
        { id: "tv", name: "TV", icon: "tv", detail: "Keep awake for couch sessions" },
        { id: "presentation", name: "Presentation", icon: "co_present", detail: "Stay awake and silence popups" }
    ]

    function captureCurrent() {
        if (captured) return;
        previousBarAutoHide = Config.options.bar.autoHide.enable;
        previousDockEnabled = Config.options.dock.enable;
        previousSilent = Notifications.silent;
        previousIdleInhibit = Idle.inhibit;
        previousPowerProfile = SystemHealth.powerProfile === "unknown" ? "balanced" : SystemHealth.powerProfile;
        captured = true;
    }

    function setPowerProfile(profile) {
        powerProfile.command = ["powerprofilesctl", "set", profile];
        powerProfile.running = false;
        powerProfile.running = true;
    }

    function apply(mode) {
        if (!modes.some(entry => entry.id === mode)) return;
        captureCurrent();
        currentMode = mode;

        if (mode === "balanced") {
            Config.options.bar.autoHide.enable = previousBarAutoHide;
            Config.options.dock.enable = previousDockEnabled;
            Notifications.silent = previousSilent;
            Idle.toggleInhibit(previousIdleInhibit);
            setPowerProfile(previousPowerProfile);
            captured = false;
            return;
        }

        const quiet = mode === "focus" || mode === "gaming" || mode === "presentation";
        const distractionFree = mode === "focus" || mode === "gaming" || mode === "presentation";
        const stayAwake = mode === "gaming" || mode === "tv" || mode === "presentation";
        Notifications.silent = quiet;
        Config.options.bar.autoHide.enable = distractionFree;
        Config.options.dock.enable = distractionFree ? false : previousDockEnabled;
        Idle.toggleInhibit(stayAwake);
        setPowerProfile(mode === "gaming" ? "performance" : "balanced");
    }

    Process { id: powerProfile }
}
