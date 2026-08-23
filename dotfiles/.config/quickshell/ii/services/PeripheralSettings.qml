pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common

Singleton {
    id: root

    property var devices: ({})
    property var mice: []
    property var keyboards: []
    property var touchDevices: []
    property var pendingSettings: ({})
    property bool pendingInitialApply: false
    readonly property string persistedHyprConfigPath: `${Directories.config}/hypr/hyprland/peripherals.lua`
    readonly property real mouseSensitivityMin: -4
    readonly property real mouseSensitivityMax: 1
    readonly property var mouseDefaults: ({
        sensitivity: 0,
        accelProfile: "",
        scrollFactor: 1,
        followMouse: 1,
        leftHanded: false
    })
    readonly property var touchpadDefaults: ({
        naturalScroll: true,
        tapToClick: true,
        tapAndDrag: true,
        disableWhileTyping: true,
        dragLock: false,
        scrollFactor: 0.5
    })
    readonly property var keyboardDefaults: ({
        numlockByDefault: true
    })
    readonly property bool refreshingDevices: devicesProc.running
    readonly property var visibleMice: root.mice.filter(device => root.isVisibleMouse(device))
    readonly property var visibleTouchpads: root.mice.filter(device => root.isTouchpadDevice(device)).concat(root.touchDevices.filter(device => !root.isIgnoredDevice(device)))
    readonly property var visibleKeyboards: root.keyboards.filter(device => root.isVisibleKeyboard(device))
    readonly property string mainKeyboardName: {
        const mainKeyboard = root.keyboards.find(device => device?.main === true);
        return mainKeyboard ? root.deviceName(mainKeyboard) : "";
    }

    function load() {
        if (!Config.ready) {
            root.pendingInitialApply = true;
            return;
        }

        root.applyAll();
        root.refreshDevices();
    }

    function applyAll() {
        root.applyMouse();
        root.applyTouchpad();
        root.applyKeyboard();
    }

    function applyMouse() {
        root.applyMouseSensitivity();
        root.applyMouseAccelProfile();
        root.applyMouseScrollFactor();
        root.applyFollowMouse();
        root.applyLeftHanded();
    }

    function applyTouchpad() {
        root.applyTouchpadNaturalScroll();
        root.applyTouchpadTapToClick();
        root.applyTouchpadTapAndDrag();
        root.applyTouchpadDisableWhileTyping();
        root.applyTouchpadDragLock();
        root.applyTouchpadScrollFactor();
    }

    function applyKeyboard() {
        root.applyNumlockByDefault();
    }

    function resetMouse() {
        if (!Config.ready)
            return;

        Config.options.peripherals.mouse.sensitivity = root.mouseDefaults.sensitivity;
        Config.options.peripherals.mouse.accelProfile = root.mouseDefaults.accelProfile;
        Config.options.peripherals.mouse.scrollFactor = root.mouseDefaults.scrollFactor;
        Config.options.peripherals.mouse.followMouse = root.mouseDefaults.followMouse;
        Config.options.peripherals.mouse.leftHanded = root.mouseDefaults.leftHanded;
        root.applyMouse();
    }

    function resetTouchpad() {
        if (!Config.ready)
            return;

        Config.options.peripherals.touchpad.naturalScroll = root.touchpadDefaults.naturalScroll;
        Config.options.peripherals.touchpad.tapToClick = root.touchpadDefaults.tapToClick;
        Config.options.peripherals.touchpad.tapAndDrag = root.touchpadDefaults.tapAndDrag;
        Config.options.peripherals.touchpad.disableWhileTyping = root.touchpadDefaults.disableWhileTyping;
        Config.options.peripherals.touchpad.dragLock = root.touchpadDefaults.dragLock;
        Config.options.peripherals.touchpad.scrollFactor = root.touchpadDefaults.scrollFactor;
        root.applyTouchpad();
    }

    function resetKeyboard() {
        if (!Config.ready)
            return;

        Config.options.peripherals.keyboard.numlockByDefault = root.keyboardDefaults.numlockByDefault;
        root.applyKeyboard();
    }

    function resetAll() {
        root.resetMouse();
        root.resetTouchpad();
        root.resetKeyboard();
        root.applyAll();
    }

    function applyConfig(path, value) {
        if (!path || !Config.ready)
            return;

        const nextPending = Object.assign({}, root.pendingSettings);
        nextPending[path] = value;
        root.pendingSettings = nextPending;
        configApplyTimer.restart();
    }

    function setLuaPath(table, path, value) {
        const parts = path.split(".");
        let target = table;

        for (let i = 0; i < parts.length - 1; i++) {
            const part = parts[i];
            if (!target[part] || typeof target[part] !== "object" || Array.isArray(target[part]))
                target[part] = ({});
            target = target[part];
        }

        target[parts[parts.length - 1]] = value;
    }

    function luaString(value) {
        return `"${`${value ?? ""}`
            .replace(/\\/g, "\\\\")
            .replace(/"/g, "\\\"")
            .replace(/\n/g, "\\n")
            .replace(/\r/g, "\\r")}"`;
    }

    function luaKey(key) {
        return /^[A-Za-z_][A-Za-z0-9_]*$/.test(key) ? key : `[${root.luaString(key)}]`;
    }

    function luaValue(value) {
        if (typeof value === "boolean")
            return value ? "true" : "false";
        if (typeof value === "number")
            return isFinite(value) ? `${value}` : "0";
        if (typeof value === "string")
            return root.luaString(value);
        if (value && typeof value === "object" && !Array.isArray(value))
            return root.luaTable(value);

        return "nil";
    }

    function luaTable(table) {
        const parts = [];
        const keys = Object.keys(table).sort();

        for (const key of keys)
            parts.push(`${root.luaKey(key)} = ${root.luaValue(table[key])}`);

        return `{ ${parts.join(", ")} }`;
    }

    function persistedPeripheralConfig() {
        const mouse = Config.options.peripherals.mouse;
        const touchpad = Config.options.peripherals.touchpad;
        const keyboard = Config.options.peripherals.keyboard;

        return {
            input: {
                sensitivity: root.roundNumber(root.clampNumber(mouse.sensitivity, root.mouseSensitivityMin, root.mouseSensitivityMax, 0), 2),
                accel_profile: root.profileValue(mouse.accelProfile),
                scroll_factor: root.roundNumber(root.clampNumber(mouse.scrollFactor, 0.25, 3, 1), 2),
                follow_mouse: Math.round(root.clampNumber(mouse.followMouse, 0, 3, 1)),
                left_handed: root.boolValue(mouse.leftHanded),
                numlock_by_default: root.boolValue(keyboard.numlockByDefault),
                touchpad: {
                    natural_scroll: root.boolValue(touchpad.naturalScroll),
                    tap_to_click: root.boolValue(touchpad.tapToClick),
                    tap_and_drag: root.boolValue(touchpad.tapAndDrag),
                    disable_while_typing: root.boolValue(touchpad.disableWhileTyping),
                    drag_lock: root.boolValue(touchpad.dragLock),
                    scroll_factor: root.roundNumber(root.clampNumber(touchpad.scrollFactor, 0.25, 3, 0.5), 2)
                }
            }
        };
    }

    function flushSettings() {
        const entries = Object.entries(root.pendingSettings);
        if (entries.length === 0)
            return;

        root.pendingSettings = ({});

        const table = ({});
        for (const entry of entries)
            root.setLuaPath(table, entry[0], entry[1]);

        const persistedConfig = `-- Generated by Quickshell PeripheralSettings.qml. Do not edit manually.\n`
            + `hl.config(${root.luaTable(root.persistedPeripheralConfig())})\n`;
        persistedHyprConfigView.setText(persistedConfig);
        Quickshell.execDetached(["hyprctl", "eval", `hl.config(${root.luaTable(table)})`]);
    }

    function clampNumber(value, min, max, fallback) {
        const parsed = Number(value);
        if (!isFinite(parsed))
            return fallback;
        return Math.max(min, Math.min(max, parsed));
    }

    function roundNumber(value, decimals = 2) {
        const parsed = Number(value);
        if (!isFinite(parsed))
            return 0;

        const factor = Math.pow(10, decimals);
        return Math.round(parsed * factor) / factor;
    }

    function boolValue(value) {
        return !!value;
    }

    function profileValue(value) {
        const profile = `${value ?? ""}`;
        return profile === "default" ? "" : profile;
    }

    function applyMouseSensitivity(value = Config.options.peripherals.mouse.sensitivity) {
        root.applyConfig("input.sensitivity", root.roundNumber(root.clampNumber(value, root.mouseSensitivityMin, root.mouseSensitivityMax, 0), 2));
    }

    function applyMouseAccelProfile(value = Config.options.peripherals.mouse.accelProfile) {
        root.applyConfig("input.accel_profile", root.profileValue(value));
    }

    function applyMouseScrollFactor(value = Config.options.peripherals.mouse.scrollFactor) {
        root.applyConfig("input.scroll_factor", root.roundNumber(root.clampNumber(value, 0.25, 3, 1), 2));
    }

    function applyFollowMouse(value = Config.options.peripherals.mouse.followMouse) {
        root.applyConfig("input.follow_mouse", Math.round(root.clampNumber(value, 0, 3, 1)));
    }

    function applyLeftHanded(value = Config.options.peripherals.mouse.leftHanded) {
        root.applyConfig("input.left_handed", root.boolValue(value));
    }

    function applyTouchpadNaturalScroll(value = Config.options.peripherals.touchpad.naturalScroll) {
        root.applyConfig("input.touchpad.natural_scroll", root.boolValue(value));
    }

    function applyTouchpadTapToClick(value = Config.options.peripherals.touchpad.tapToClick) {
        root.applyConfig("input.touchpad.tap_to_click", root.boolValue(value));
    }

    function applyTouchpadTapAndDrag(value = Config.options.peripherals.touchpad.tapAndDrag) {
        root.applyConfig("input.touchpad.tap_and_drag", root.boolValue(value));
    }

    function applyTouchpadDisableWhileTyping(value = Config.options.peripherals.touchpad.disableWhileTyping) {
        root.applyConfig("input.touchpad.disable_while_typing", root.boolValue(value));
    }

    function applyTouchpadDragLock(value = Config.options.peripherals.touchpad.dragLock) {
        root.applyConfig("input.touchpad.drag_lock", root.boolValue(value));
    }

    function applyTouchpadScrollFactor(value = Config.options.peripherals.touchpad.scrollFactor) {
        root.applyConfig("input.touchpad.scroll_factor", root.roundNumber(root.clampNumber(value, 0.25, 3, 0.5), 2));
    }

    function applyNumlockByDefault(value = Config.options.peripherals.keyboard.numlockByDefault) {
        root.applyConfig("input.numlock_by_default", root.boolValue(value));
    }

    FileView {
        id: persistedHyprConfigView
        path: root.persistedHyprConfigPath
        watchChanges: false
        blockWrites: false
    }

    function refreshDevices() {
        if (!devicesProc.running)
            devicesProc.running = true;
    }

    function deviceName(device) {
        return `${device?.name ?? ""}`;
    }

    function isIgnoredDevice(device) {
        const name = root.deviceName(device).toLowerCase();
        return !name
            || name.includes("virtual")
            || name.includes("ydotool")
            || name.includes("consumer-control")
            || name.includes("system-control")
            || name.includes("power-button")
            || name.includes("sleep-button")
            || name.includes("video-bus");
    }

    function isTouchpadDevice(device) {
        const name = root.deviceName(device).toLowerCase();
        return name.includes("touchpad") || name.includes("trackpad");
    }

    function isVisibleMouse(device) {
        return !root.isIgnoredDevice(device) && !root.isTouchpadDevice(device);
    }

    function isVisibleKeyboard(device) {
        return !root.isIgnoredDevice(device);
    }

    Process {
        id: devicesProc
        command: ["hyprctl", "-j", "devices"]

        stdout: StdioCollector {
            id: devicesCollector

            onStreamFinished: {
                try {
                    const parsed = JSON.parse(devicesCollector.text || "{}");
                    root.devices = parsed;
                    root.mice = Array.isArray(parsed?.mice) ? parsed.mice : [];
                    root.keyboards = Array.isArray(parsed?.keyboards) ? parsed.keyboards : [];
                    root.touchDevices = Array.isArray(parsed?.touch) ? parsed.touch : [];
                } catch (error) {
                    console.warn(`[PeripheralSettings] Failed to parse hyprctl devices: ${error}`);
                }
            }
        }
    }

    Timer {
        id: configApplyTimer
        interval: 75
        repeat: false
        onTriggered: root.flushSettings()
    }

    Connections {
        target: Config

        function onReadyChanged() {
            if (Config.ready && root.pendingInitialApply) {
                root.pendingInitialApply = false;
                root.applyAll();
                root.refreshDevices();
            }
        }
    }

    Connections {
        target: Config.options.peripherals.mouse

        function onSensitivityChanged() { root.applyMouseSensitivity(); }
        function onAccelProfileChanged() { root.applyMouseAccelProfile(); }
        function onScrollFactorChanged() { root.applyMouseScrollFactor(); }
        function onFollowMouseChanged() { root.applyFollowMouse(); }
        function onLeftHandedChanged() { root.applyLeftHanded(); }
    }

    Connections {
        target: Config.options.peripherals.touchpad

        function onNaturalScrollChanged() { root.applyTouchpadNaturalScroll(); }
        function onTapToClickChanged() { root.applyTouchpadTapToClick(); }
        function onTapAndDragChanged() { root.applyTouchpadTapAndDrag(); }
        function onDisableWhileTypingChanged() { root.applyTouchpadDisableWhileTyping(); }
        function onDragLockChanged() { root.applyTouchpadDragLock(); }
        function onScrollFactorChanged() { root.applyTouchpadScrollFactor(); }
    }

    Connections {
        target: Config.options.peripherals.keyboard

        function onNumlockByDefaultChanged() { root.applyNumlockByDefault(); }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "deviceadded" || event.name === "deviceremoved" || event.name === "configreloaded")
                root.refreshDevices();
        }
    }
}
