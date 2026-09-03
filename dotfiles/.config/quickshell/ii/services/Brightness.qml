pragma Singleton
pragma ComponentBehavior: Bound

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

/**
 * For managing brightness of monitors. Supports both brightnessctl and ddcutil.
 */
Singleton {
    id: root
    signal brightnessChanged()

    property var ddcMonitors: []
    property bool ddcDetectionQueued: false
    property var lastChangedMonitor: null
    property list<string> softwareDimmingScreens: ["HDMI-A-1"]
    readonly property string ddcDetectScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/system/detect-ddc-monitors.py`
    readonly property list<BrightnessMonitor> monitors: Quickshell.screens.map(screen => monitorComp.createObject(root, {
        screen
    }))

    function getMonitorForScreen(screen: ShellScreen): var {
        if (!screen)
            return null;
        return monitors.find(m => m.screen === screen)
            ?? monitors.find(m => m.screen?.name === screen.name)
            ?? null;
    }

    function increaseBrightness(): void {
        const focusedName = Hyprland.focusedMonitor.name;
        const monitor = monitors.find(m => focusedName === m.screen.name);
        if (monitor)
            monitor.setBrightness(monitor.brightness + 0.05);
    }

    function decreaseBrightness(): void {
        const focusedName = Hyprland.focusedMonitor.name;
        const monitor = monitors.find(m => focusedName === m.screen.name);
        if (monitor)
            monitor.setBrightness(monitor.brightness - 0.05);
    }

    reloadableId: "brightness"

    onMonitorsChanged: {
        ddcDetectDelay.restart();
    }

    Timer {
        id: ddcDetectDelay
        interval: 800
        repeat: false
        onTriggered: root.startDdcDetection()
    }

    function startDdcDetection(): void {
        if (ddcProc.running) {
            root.ddcDetectionQueued = true;
            return;
        }
        root.ddcDetectionQueued = false;
        root.ddcMonitors = [];
        ddcProc.running = true;
    }

    function initializeMonitor(i: int): void {
        if (i >= monitors.length)
            return;
        monitors[i].initialize();
    }

    function applyDdcDetection(output: string): bool {
        try {
            const payload = JSON.parse(output || "{}");
            if (payload.schema !== "quickshell.ddc-monitors.v1" || payload.ok !== true
                    || !Array.isArray(payload.monitors))
                return false;

            const screenNames = new Set(root.monitors.map(monitor => monitor.screen?.name ?? ""));
            root.ddcMonitors = payload.monitors.map(monitor => ({
                name: `${monitor?.connector ?? ""}`,
                busNum: `${monitor?.bus ?? ""}`
            })).filter(monitor => screenNames.has(monitor.name) && /^\d+$/.test(monitor.busNum));
            return true;
        } catch (error) {
            console.warn(`Could not parse DDC monitor discovery: ${error}`);
            return false;
        }
    }

    Process {
        id: ddcProc

        command: [
            "python3", root.ddcDetectScriptPath,
            ...root.monitors.map(monitor => monitor.screen?.name ?? "").filter(name => name.length > 0).sort()
        ]
        stdout: StdioCollector {
            id: ddcOutput
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.applyDdcDetection(ddcOutput.text);
            if (root.ddcDetectionQueued) {
                Qt.callLater(() => root.startDdcDetection());
                return;
            }
            root.initializeMonitor(0);
        }
    }

    Process {
        id: setProc
    }

    component BrightnessMonitor: QtObject {
        id: monitor

        required property ShellScreen screen
        property bool isDdc
        property string busNum
        property int rawMaxBrightness: 100
        property real brightness
        property real brightnessMultiplier: 1.0
        property real multipliedBrightness: Math.max(0, Math.min(1, brightness * (Config.options.light.antiFlashbang.enable ? brightnessMultiplier : 1)))
        property bool ready: false
        property bool usesSoftwareDimming: false
        property bool animateChanges: !monitor.isDdc

        onBrightnessChanged: {
            if (!monitor.ready) return;
            root.lastChangedMonitor = monitor;
            root.brightnessChanged();
        }

        Behavior on multipliedBrightness {
            enabled: monitor.animateChanges
            NumberAnimation {
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
        onMultipliedBrightnessChanged: {
            if (monitor.animationEnabled) syncBrightness();
            else setTimer.restart();
        }

        function initialize() {
            monitor.ready = false;
            monitor.usesSoftwareDimming = false;
            if (root.softwareDimmingScreens.includes(screen.name)) {
                monitor.enableSoftwareDimming();
                monitor.finishInitialization();
                return;
            }

            const match = root.ddcMonitors.find(m => m.name === screen.name && !root.monitors.slice(0, root.monitors.indexOf(this)).some(mon => mon.busNum === m.busNum));
            isDdc = !!match;
            busNum = match?.busNum ?? "";
            initProc.command = isDdc ? ["ddcutil", "-b", busNum, "getvcp", "10", "--brief"] : ["sh", "-c", `echo "backlight $(brightnessctl --class backlight g 2>/dev/null) $(brightnessctl --class backlight m 2>/dev/null)"`];
            initProc.running = true;
        }

        function enableSoftwareDimming() {
            monitor.isDdc = false;
            monitor.busNum = "";
            monitor.rawMaxBrightness = 100;
            if (!isFinite(monitor.brightness) || monitor.brightness <= 0)
                monitor.brightness = 1;
            monitor.usesSoftwareDimming = true;
            monitor.ready = true;
        }

        function finishInitialization() {
            initializeMonitor(root.monitors.indexOf(monitor) + 1);
        }

        readonly property Process initProc: Process {
            stdout: SplitParser {
                onRead: data => {
                    const fields = data.trim().split(/\s+/);
                    const current = monitor.isDdc ? parseInt(fields[3], 10) : parseInt(fields[1], 10);
                    const max = monitor.isDdc ? parseInt(fields[4], 10) : parseInt(fields[2], 10);
                    if (isNaN(current) || isNaN(max) || max <= 0)
                        return;

                    monitor.rawMaxBrightness = max;
                    monitor.brightness = Math.max(0, Math.min(1, current / monitor.rawMaxBrightness));
                    monitor.ready = true;
                }
            }
            onExited: (exitCode, exitStatus) => {
                if (!monitor.ready)
                    monitor.enableSoftwareDimming();
                monitor.finishInitialization();
            }
        }

        // We need a delay for DDC monitors because they can be quite slow and might act weird with rapid changes
        property var setTimer: Timer {
            id: setTimer
            interval: monitor.isDdc ? 300 : 0
            onTriggered: {
                syncBrightness();
            }
        }

        function syncBrightness() {
            if (!monitor.ready)
                return;

            const brightnessValue = Math.max(monitor.multipliedBrightness, 0);
            if (monitor.usesSoftwareDimming) {
                return;
            } else if (isDdc) {
                const rawValueRounded = Math.max(Math.floor(brightnessValue * monitor.rawMaxBrightness), 1);
                setProc.exec(["ddcutil", "--noverify", "-b", busNum, "setvcp", "10", rawValueRounded]);
            } else {
                const valuePercentNumber = Math.floor(brightnessValue * 100);
                let valuePercent = `${valuePercentNumber}%`;
                if (valuePercentNumber == 0) valuePercent = "1"; // Prevent fully black
                setProc.exec(["brightnessctl", "--class", "backlight", "s", valuePercent, "--quiet"])
            }
        }

        function setBrightness(value: real): void {
            if (!monitor.ready)
                return;

            value = Math.max(0, Math.min(1, value));
            monitor.brightness = value;
        }

        function setBrightnessMultiplier(value: real): void {
            monitor.brightnessMultiplier = value;
        }
    }

    Component {
        id: monitorComp

        BrightnessMonitor {}
    }

    // Anti-flashbang
    property int workspaceAnimationDelay: 500
    property int contentSwitchDelay: 30
    property string screenshotDir: "/tmp/quickshell/brightness/antiflashbang"
    function brightnessMultiplierForLightness(x: real): real {
        // I hand picked some values and fitted an exponential curve for this
        // 6.600135 + 216.360356 * e^(-0.0811129189x)
        // Division by 100 is to normalize to [0, 1]
        return (6.600135 + 216.360356 * Math.pow(Math.E, -0.0811129189 * x)) / 100.0;
    }
    Variants {
        model: Quickshell.screens
        Scope {
            id: screenScope
            required property var modelData
            property string screenName: modelData.name
            property string screenshotPath: `${root.screenshotDir}/screenshot-${screenName}.png`
            Connections {
                enabled: Config.options.light.antiFlashbang.enable && Appearance.m3colors.darkmode
                target: Hyprland
                function onRawEvent(event) {
                    if (["activewindowv2", "windowtitlev2"].includes(event.name)) {
                        screenshotTimer.interval = root.contentSwitchDelay;
                        screenshotTimer.restart();
                    } else if (["workspacev2"].includes(event.name)) {
                        screenshotTimer.interval = root.workspaceAnimationDelay;
                        screenshotTimer.restart();
                    }
                }
            }

            Timer {
                id: screenshotTimer
                interval: 700 // This is what I have for a Hyprland ws anim
                onTriggered: {
                    screenshotProc.running = false;
                    screenshotProc.running = true;
                }
            }

            Process {
                id: screenshotProc
                command: ["bash", "-c",
                    `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.screenshotDir)}'`
                    + ` && grim -o '${StringUtils.shellSingleQuoteEscape(screenScope.screenName)}' -`
                    + ` | magick png:- -colorspace Gray -format "%[fx:mean*100]" info:`
                ]
                stdout: StdioCollector {
                    id: lightnessCollector
                    onStreamFinished: {
                        Quickshell.execDetached(["rm", screenScope.screenshotPath]); // Cleanup
                        const lightness = lightnessCollector.text
                        const newMultiplier = root.brightnessMultiplierForLightness(parseFloat(lightness))
                        Brightness.getMonitorForScreen(screenScope.modelData).setBrightnessMultiplier(newMultiplier)
                    }
                }
            }
        }
    }

    // External trigger points

    IpcHandler {
        target: "brightness"

        function increment() {
            onPressed: root.increaseBrightness()
        }

        function decrement() {
            onPressed: root.decreaseBrightness()
        }
    }

    GlobalShortcut {
        name: "brightnessIncrease"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }

    GlobalShortcut {
        name: "brightnessDecrease"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }
}
