import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760

    readonly property var accelProfileOptions: [
        { displayName: Translation.tr("Default"), icon: "radio_button_checked", value: "default" },
        { displayName: Translation.tr("Adaptive"), icon: "speed", value: "adaptive" },
        { displayName: Translation.tr("Flat"), icon: "linear_scale", value: "flat" }
    ]
    readonly property var followMouseOptions: [
        { displayName: Translation.tr("Off"), icon: "block", value: 0 },
        { displayName: Translation.tr("Normal"), icon: "near_me", value: 1 },
        { displayName: Translation.tr("Loose"), icon: "open_with", value: 2 },
        { displayName: Translation.tr("Strict"), icon: "my_location", value: 3 }
    ]
    readonly property var deviceRows: root.buildDeviceRows()
    property int m75PollingRateHz: 1000
    property string m75LightingMode: "static"
    property int m75LightingBrightness: 4
    property int m75LightingSpeed: 2
    property int m75LightingRed: 255
    property int m75LightingGreen: 255
    property int m75LightingBlue: 255
    property real m75ActuationMm: 2
    property bool m75RapidTriggerEnabled: false
    property real m75RapidTriggerSensitivityMm: 0.2
    property bool m75Loading: false
    property bool m75PollingDirty: false
    property bool m75LightingDirty: false
    property bool m75ActuationDirty: false
    property bool m75RapidTriggerDirty: false
    readonly property color m75LightingColor: Qt.rgba(root.m75LightingRed / 255, root.m75LightingGreen / 255, root.m75LightingBlue / 255, 1)
    readonly property var m75PollingRateOptions: root.buildM75PollingRateOptions()
    readonly property var m75LightingModeOptions: root.buildM75LightingModeOptions()
    readonly property bool m75HasWritableSettings: root.m75FeatureWritable("polling_rate")
        || root.m75FeatureWritable("rgb")
        || root.m75FeatureWritable("actuation")
        || root.m75FeatureWritable("rapid_trigger")
    property int g502Dpi: 3200
    property string g502ReportRate: "2ms"
    property string g502OnboardProfile: "Disabled"
    property bool g502InvertScroll: false
    readonly property bool g502OnboardDisabled: root.g502OnboardProfile.toLowerCase() === "disabled"
    readonly property var g502ReportRateOptions: root.g502Options("report_rate", ["1ms", "2ms", "4ms", "8ms"], "speed")
    readonly property var g502ProfileOptions: root.g502Options("onboard_profile", ["Disabled", "Profile 1", "Profile 2"], "memory")
    property string appliedMouseState: ""
    property string appliedTouchpadState: ""
    property string appliedKeyboardState: ""
    property bool deviceListExpanded: false
    readonly property string mouseState: [
        Config.options.peripherals.mouse.sensitivity,
        Config.options.peripherals.mouse.accelProfile,
        Config.options.peripherals.mouse.scrollFactor,
        Config.options.peripherals.mouse.followMouse,
        Config.options.peripherals.mouse.leftHanded
    ].join("|")
    readonly property string touchpadState: [
        Config.options.peripherals.touchpad.naturalScroll,
        Config.options.peripherals.touchpad.tapToClick,
        Config.options.peripherals.touchpad.tapAndDrag,
        Config.options.peripherals.touchpad.disableWhileTyping,
        Config.options.peripherals.touchpad.dragLock,
        Config.options.peripherals.touchpad.scrollFactor
    ].join("|")
    readonly property string keyboardState: `${Config.options.peripherals.keyboard.numlockByDefault}`
    readonly property bool mouseDirty: root.appliedMouseState.length > 0 && root.mouseState !== root.appliedMouseState
    readonly property bool touchpadDirty: root.appliedTouchpadState.length > 0 && root.touchpadState !== root.appliedTouchpadState
    readonly property bool keyboardDirty: root.appliedKeyboardState.length > 0 && root.keyboardState !== root.appliedKeyboardState

    function captureAppliedStates() {
        root.appliedMouseState = root.mouseState;
        root.appliedTouchpadState = root.touchpadState;
        root.appliedKeyboardState = root.keyboardState;
    }

    function applyMouseDraft() {
        PeripheralSettings.applyMouse();
        root.appliedMouseState = root.mouseState;
    }

    function applyTouchpadDraft() {
        PeripheralSettings.applyTouchpad();
        root.appliedTouchpadState = root.touchpadState;
    }

    function applyKeyboardDraft() {
        PeripheralSettings.applyKeyboard();
        root.appliedKeyboardState = root.keyboardState;
    }

    function resetMouseDraft() {
        const defaults = PeripheralSettings.mouseDefaults;
        Config.options.peripherals.mouse.sensitivity = defaults.sensitivity;
        Config.options.peripherals.mouse.accelProfile = defaults.accelProfile;
        Config.options.peripherals.mouse.scrollFactor = defaults.scrollFactor;
        Config.options.peripherals.mouse.followMouse = defaults.followMouse;
        Config.options.peripherals.mouse.leftHanded = defaults.leftHanded;
    }

    function resetTouchpadDraft() {
        const defaults = PeripheralSettings.touchpadDefaults;
        Config.options.peripherals.touchpad.naturalScroll = defaults.naturalScroll;
        Config.options.peripherals.touchpad.tapToClick = defaults.tapToClick;
        Config.options.peripherals.touchpad.tapAndDrag = defaults.tapAndDrag;
        Config.options.peripherals.touchpad.disableWhileTyping = defaults.disableWhileTyping;
        Config.options.peripherals.touchpad.dragLock = defaults.dragLock;
        Config.options.peripherals.touchpad.scrollFactor = defaults.scrollFactor;
    }

    function resetKeyboardDraft() {
        Config.options.peripherals.keyboard.numlockByDefault = PeripheralSettings.keyboardDefaults.numlockByDefault;
    }

    function rounded(value, decimals = 2) {
        const parsed = Number(value);
        return isFinite(parsed) ? parsed.toFixed(decimals) : "0.00";
    }

    function deviceLabel(device) {
        return `${device?.name ?? Translation.tr("Unknown device")}`;
    }

    function deviceDetail(device, category) {
        const details = [];

        if (category)
            details.push(category);
        if (device?.main === true)
            details.push(Translation.tr("Main"));
        if (device?.active_keymap)
            details.push(`${Translation.tr("Layout")}: ${device.active_keymap}`);
        else if (device?.layout)
            details.push(`${Translation.tr("Layouts")}: ${device.layout}`);

        return details.join(" | ");
    }

    function buildDeviceRows() {
        const rows = [];

        for (const device of PeripheralSettings.visibleMice)
            rows.push({ icon: "mouse", label: root.deviceLabel(device), detail: root.deviceDetail(device, Translation.tr("Mouse")) });
        for (const device of PeripheralSettings.visibleTouchpads)
            rows.push({ icon: "touchpad_mouse", label: root.deviceLabel(device), detail: root.deviceDetail(device, Translation.tr("Touchpad")) });
        for (const device of PeripheralSettings.visibleKeyboards)
            rows.push({ icon: "keyboard", label: root.deviceLabel(device), detail: root.deviceDetail(device, Translation.tr("Keyboard")) });

        return rows;
    }

    function m75DriverDetail() {
        if (!MechlandsM75.backendAvailable)
            return Translation.tr("Driver unavailable");
        if (!MechlandsM75.connected)
            return Translation.tr("Disconnected");
        if (MechlandsM75.configurationAvailable)
            return Translation.tr("Configuration available");
        return Translation.tr("Read-only research mode");
    }

    function m75CapabilityDetail(feature) {
        const isReadOnly = feature?.status === "read-only";
        const status = feature?.status === "available"
            ? Translation.tr("Available")
            : feature?.status === "supported"
                ? Translation.tr("Supported")
                : feature?.status === "experimental"
                    ? Translation.tr("Experimental")
                : feature?.status === "unavailable"
                    ? Translation.tr("Unavailable")
                    : isReadOnly
                        ? Translation.tr("Read-only")
                        : Translation.tr("Research");
        return feature?.writable === true || isReadOnly
            ? status
            : `${status} | ${Translation.tr("Read-only")}`;
    }

    function m75Feature(id) {
        return MechlandsM75.features.find(feature => feature?.id === id) ?? null;
    }

    function m75FeatureWritable(id) {
        const feature = root.m75Feature(id);
        return MechlandsM75.configurationAvailable
            && feature?.writable === true
            && (feature?.status === "available"
                || feature?.status === "supported"
                || feature?.status === "experimental");
    }

    function m75FeatureField(id, fieldId) {
        return root.m75Feature(id)?.fields?.[fieldId] ?? null;
    }

    function m75FeatureRange(id, fieldId = "") {
        return (fieldId ? root.m75FeatureField(id, fieldId) : null)
            ?? root.m75Feature(id)?.range
            ?? {};
    }

    function m75FeatureOptions(id, fallback, fieldId = "") {
        const feature = root.m75Feature(id);
        const field = fieldId ? root.m75FeatureField(id, fieldId) : null;
        const options = field?.options ?? field?.values ?? feature?.options ?? feature?.values;
        return Array.isArray(options) && options.length > 0 ? options : fallback;
    }

    function buildM75PollingRateOptions() {
        return root.m75FeatureOptions("polling_rate", [125, 250, 500, 1000, 2000, 4000, 8000])
            .map(value => ({ displayName: `${value} Hz`, icon: "speed", value: Number(value) }));
    }

    function m75LightingModeLabel(mode) {
        const labels = {
            "off": Translation.tr("Off"),
            "static": Translation.tr("Static"),
            "breathing": Translation.tr("Breathing"),
            "wave": Translation.tr("Wave"),
            "reactive": Translation.tr("Reactive"),
            "spectrum": Translation.tr("Spectrum"),
            "ripple": Translation.tr("Ripple"),
            "raindrop": Translation.tr("Raindrop"),
            "snake": Translation.tr("Snake"),
            "convergence": Translation.tr("Convergence"),
            "sine_wave": Translation.tr("Sine wave"),
            "kaleidoscope": Translation.tr("Kaleidoscope"),
            "line_wave": Translation.tr("Line wave"),
            "laser": Translation.tr("Laser"),
            "circle_wave": Translation.tr("Circle wave"),
            "dazzle": Translation.tr("Dazzle"),
            "rain": Translation.tr("Rain"),
            "meteor": Translation.tr("Meteor"),
            "reactive_off": Translation.tr("Reactive off"),
            "train": Translation.tr("Train"),
            "fireworks": Translation.tr("Fireworks")
        };
        return labels[mode] ?? `${mode}`;
    }

    function buildM75LightingModeOptions() {
        return root.m75FeatureOptions("rgb", ["off", "static", "breathing", "wave", "reactive", "spectrum"], "mode")
            .map(value => ({ displayName: root.m75LightingModeLabel(`${value}`), icon: "palette", value: `${value}` }));
    }

    function m75Number(value, fallback) {
        const parsed = Number(value);
        return isFinite(parsed) ? parsed : fallback;
    }

    function m75RoundStep(value, step) {
        const safeStep = Math.max(0.000001, root.m75Number(step, 1));
        return Math.round(root.m75Number(value, 0) / safeStep) * safeStep;
    }

    function loadM75Settings() {
        const settings = MechlandsM75.status?.settings ?? {};
        const lighting = settings?.lighting ?? settings?.rgb ?? {};
        const color = lighting?.color ?? {};
        const rapidTrigger = settings?.rapid_trigger ?? {};

        root.m75Loading = true;
        root.m75PollingRateHz = Math.round(root.m75Number(settings?.polling_rate_hz, 1000));
        root.m75LightingMode = `${lighting?.mode ?? "static"}`;
        root.m75LightingBrightness = Math.round(root.m75Number(lighting?.brightness, 4));
        root.m75LightingSpeed = Math.round(root.m75Number(lighting?.speed, 2));
        root.m75LightingRed = Math.round(root.m75Number(color?.r, 255));
        root.m75LightingGreen = Math.round(root.m75Number(color?.g, 255));
        root.m75LightingBlue = Math.round(root.m75Number(color?.b, 255));
        root.m75ActuationMm = root.m75Number(settings?.actuation_mm, 2);
        root.m75RapidTriggerEnabled = rapidTrigger?.enabled === true;
        root.m75RapidTriggerSensitivityMm = root.m75Number(rapidTrigger?.sensitivity_mm, 0.2);
        root.m75PollingDirty = false;
        root.m75LightingDirty = false;
        root.m75ActuationDirty = false;
        root.m75RapidTriggerDirty = false;
        root.m75Loading = false;
    }

    function applyM75Settings() {
        const payload = ({});

        if (root.m75PollingDirty && root.m75FeatureWritable("polling_rate"))
            payload.polling_rate_hz = root.m75PollingRateHz;
        if (root.m75LightingDirty && root.m75FeatureWritable("rgb")) {
            payload.lighting = {
                mode: root.m75LightingMode,
                brightness: root.m75LightingBrightness,
                speed: root.m75LightingSpeed,
                color: {
                    r: root.m75LightingRed,
                    g: root.m75LightingGreen,
                    b: root.m75LightingBlue
                }
            };
        }
        if (root.m75ActuationDirty && root.m75FeatureWritable("actuation"))
            payload.actuation_mm = root.m75ActuationMm;
        if (root.m75RapidTriggerDirty && root.m75FeatureWritable("rapid_trigger")) {
            payload.rapid_trigger = {
                enabled: root.m75RapidTriggerEnabled,
                sensitivity_mm: root.m75RapidTriggerSensitivityMm
            };
        }

        if (Object.keys(payload).length > 0)
            MechlandsM75.apply(payload);
    }

    function g502Boolean(value) {
        return `${value}`.toLowerCase() === "true" || `${value}` === "1" || `${value}`.toLowerCase() === "on";
    }

    function g502Options(name, fallback, icon) {
        return LogitechG502.settingOptions(name, fallback)
            .map(value => ({ displayName: `${value}`, icon: icon, value: `${value}` }));
    }

    function loadG502Settings() {
        root.g502Dpi = Math.round(root.m75Number(LogitechG502.settingValue("dpi", "3200"), 3200));
        root.g502ReportRate = LogitechG502.settingValue("report_rate", "2ms");
        root.g502OnboardProfile = LogitechG502.settingValue("onboard_profile", "Disabled");
        root.g502InvertScroll = root.g502Boolean(LogitechG502.settingValue("scroll_invert", "False"));
    }

    function g502BatteryDetail() {
        if (!LogitechG502.connected)
            return Translation.tr("Disconnected");
        if (LogitechG502.battery?.capacity === undefined || LogitechG502.battery?.capacity === null)
            return Translation.tr("Connected");
        return `${Translation.tr("Battery: %1%").arg(LogitechG502.battery.capacity)} | ${Translation.tr(LogitechG502.battery?.status || "Unknown")}`;
    }

    Component.onCompleted: {
        PeripheralSettings.refreshDevices();
        MechlandsM75.refresh();
        LogitechG502.refresh();
        Qt.callLater(root.captureAppliedStates);
    }

    Connections {
        target: MechlandsM75

        function onStatusChanged() {
            root.loadM75Settings();
        }
    }

    Connections {
        target: LogitechG502

        function onStatusChanged() {
            root.loadG502Settings();
        }
    }

    ContentSection {
        icon: "devices"
        title: Translation.tr("Connected devices")
        description: root.deviceRows.length === 0
            ? Translation.tr("No physical input devices detected")
            : Translation.tr("%1 input devices reported by Hyprland").arg(root.deviceRows.length)

        RowLayout {
            Layout.fillWidth: true

            Item {
                Layout.fillWidth: true
            }

            IconToolbarButton {
                visible: root.deviceRows.length > 2
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                text: root.deviceListExpanded ? "expand_less" : "expand_more"
                onClicked: root.deviceListExpanded = !root.deviceListExpanded

                StyledToolTip {
                    text: root.deviceListExpanded
                        ? Translation.tr("Show fewer devices")
                        : Translation.tr("Show all devices")
                }
            }

            IconToolbarButton {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                text: PeripheralSettings.refreshingDevices ? "progress_activity" : "refresh"
                enabled: !PeripheralSettings.refreshingDevices
                onClicked: PeripheralSettings.refreshDevices()

                StyledToolTip { text: Translation.tr("Refresh devices") }
            }
        }

        Repeater {
            model: root.deviceListExpanded ? root.deviceRows : root.deviceRows.slice(0, 2)

            delegate: DeviceChip {
                required property var modelData
                icon: modelData.icon
                label: modelData.label
                detail: modelData.detail
            }
        }
    }

    ContentSection {
        icon: "mouse"
        title: Translation.tr("Mouse")
        description: Translation.tr("Pointer speed, scrolling and focus behavior")

        ConfigSlider {
            text: `${Translation.tr("Sensitivity")} (${root.rounded(Config.options.peripherals.mouse.sensitivity)})`
            buttonIcon: "speed"
            textWidth: 200
            value: Config.options.peripherals.mouse.sensitivity
            from: PeripheralSettings.mouseSensitivityMin
            to: PeripheralSettings.mouseSensitivityMax
            stopIndicatorValues: [-3, -2, -1, 0]
            usePercentTooltip: false
            onValueChanged: Config.options.peripherals.mouse.sensitivity = value
        }

        ConfigSlider {
            text: `${Translation.tr("Wheel speed")} (${root.rounded(Config.options.peripherals.mouse.scrollFactor)})`
            buttonIcon: "swap_vert"
            textWidth: 200
            value: Config.options.peripherals.mouse.scrollFactor
            from: 0.05
            to: 2
            stepSize: 0.05
            stopIndicatorValues: [0.25, 0.5, 1, 1.5]
            usePercentTooltip: false
            tooltipDecimals: 2
            onValueChanged: Config.options.peripherals.mouse.scrollFactor = value
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("1.00 is the normal distance; 2.00 doubles how far each wheel notch moves without adding extra wheel events.")
        }

        ContentSubsection {
            title: Translation.tr("Acceleration")

            ConfigSelectionArray {
                currentValue: Config.options.peripherals.mouse.accelProfile || "default"
                onSelected: newValue => Config.options.peripherals.mouse.accelProfile = newValue === "default" ? "" : newValue
                options: root.accelProfileOptions
            }
        }

        ContentSubsection {
            title: Translation.tr("Pointer focus")

            ConfigSelectionArray {
                currentValue: Config.options.peripherals.mouse.followMouse
                onSelected: newValue => Config.options.peripherals.mouse.followMouse = newValue
                options: root.followMouseOptions
            }
        }

        ConfigSwitch {
            buttonIcon: "left_click"
            text: Translation.tr("Left-handed mouse")
            checked: Config.options.peripherals.mouse.leftHanded
            onCheckedChanged: Config.options.peripherals.mouse.leftHanded = checked
        }

        SettingsActionBar {
            pending: root.mouseDirty
            applyText: Translation.tr("Apply mouse")
            onApplyRequested: root.applyMouseDraft()
            onResetRequested: root.resetMouseDraft()
        }
    }

    ContentSection {
        icon: "touchpad_mouse"
        title: Translation.tr("Touchpad")
        description: Translation.tr("Gestures, scrolling and typing protection")

        ConfigSlider {
            text: `${Translation.tr("Scroll factor")} (${root.rounded(Config.options.peripherals.touchpad.scrollFactor)})`
            buttonIcon: "swap_vert"
            textWidth: 200
            value: Config.options.peripherals.touchpad.scrollFactor
            from: 0.25
            to: 3
            stopIndicatorValues: [0.5, 1]
            usePercentTooltip: false
            onValueChanged: Config.options.peripherals.touchpad.scrollFactor = value
        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "swap_vert"
                text: Translation.tr("Natural scroll")
                checked: Config.options.peripherals.touchpad.naturalScroll
                onCheckedChanged: Config.options.peripherals.touchpad.naturalScroll = checked
            }

            ConfigSwitch {
                buttonIcon: "touch_app"
                text: Translation.tr("Tap-to-click")
                checked: Config.options.peripherals.touchpad.tapToClick
                onCheckedChanged: Config.options.peripherals.touchpad.tapToClick = checked
            }
        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "open_with"
                text: Translation.tr("Tap and drag")
                checked: Config.options.peripherals.touchpad.tapAndDrag
                onCheckedChanged: Config.options.peripherals.touchpad.tapAndDrag = checked
            }

            ConfigSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Disable while typing")
                checked: Config.options.peripherals.touchpad.disableWhileTyping
                onCheckedChanged: Config.options.peripherals.touchpad.disableWhileTyping = checked
            }
        }

        ConfigSwitch {
            buttonIcon: "lock"
            text: Translation.tr("Drag lock")
            checked: Config.options.peripherals.touchpad.dragLock
            onCheckedChanged: Config.options.peripherals.touchpad.dragLock = checked
        }

        SettingsActionBar {
            pending: root.touchpadDirty
            applyText: Translation.tr("Apply touchpad")
            onApplyRequested: root.applyTouchpadDraft()
            onResetRequested: root.resetTouchpadDraft()
        }
    }

    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Keyboard")
        description: Translation.tr("Default behavior for standard keyboards")

        ConfigSwitch {
            buttonIcon: "looks_one"
            text: Translation.tr("Numlock by default")
            checked: Config.options.peripherals.keyboard.numlockByDefault
            onCheckedChanged: Config.options.peripherals.keyboard.numlockByDefault = checked
        }

        SettingsActionBar {
            pending: root.keyboardDirty
            applyText: Translation.tr("Apply keyboard")
            onApplyRequested: root.applyKeyboardDraft()
            onResetRequested: root.resetKeyboardDraft()
        }
    }

    ContentSection {
        icon: "keyboard"
        title: Translation.tr("MechLands M75")
        description: Translation.tr("Hardware profile, lighting and magnetic switches")

        DeviceChip {
            icon: MechlandsM75.connected ? "keyboard" : "keyboard_off"
            label: MechlandsM75.device?.name || Translation.tr("MechLands M75 keyboard")
            detail: root.m75DriverDetail()
        }

        StyledText {
            visible: MechlandsM75.backendAvailable
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: `${Translation.tr("Device ID: %1").arg(MechlandsM75.capabilities?.device_id || "3151:502d")} | ${Translation.tr("HID interfaces: %1").arg(MechlandsM75.interfaces.length)}`
        }

        StyledText {
            visible: !MechlandsM75.backendAvailable || !MechlandsM75.configurationAvailable
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: MechlandsM75.backendAvailable
                ? Translation.tr("Hardware writes stay disabled until the USB protocol is verified.")
                : Translation.tr("Install the open-source MechLands driver to inspect this keyboard.")
        }

        StyledText {
            visible: MechlandsM75.lastError.length > 0 || MechlandsM75.driverError.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            wrapMode: Text.Wrap
            color: Appearance.colors.colError
            text: MechlandsM75.lastError || MechlandsM75.driverError
        }

        StyledText {
            visible: root.m75Feature("actuation")?.status === "experimental"
                || root.m75Feature("rapid_trigger")?.status === "experimental"
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Actuation and Rapid Trigger writes are experimental. Reconnect the keyboard before retrying an interrupted magnetic change.")
        }

        ContentSubsection {
            visible: root.m75FeatureWritable("polling_rate")
            title: Translation.tr("Polling rate")

            ConfigSelectionArray {
                currentValue: root.m75PollingRateHz
                options: root.m75PollingRateOptions
                onSelected: newValue => {
                    root.m75PollingRateHz = Number(newValue);
                    if (!root.m75Loading)
                        root.m75PollingDirty = true;
                }
            }
        }

        ContentSubsection {
            visible: root.m75FeatureWritable("rgb")
            title: Translation.tr("Keyboard lighting")

            ConfigSelectionArray {
                currentValue: root.m75LightingMode
                options: root.m75LightingModeOptions
                onSelected: newValue => {
                    root.m75LightingMode = `${newValue}`;
                    if (!root.m75Loading)
                        root.m75LightingDirty = true;
                }
            }

            ConfigSlider {
                text: `${Translation.tr("Brightness")} (${Math.round(root.m75LightingBrightness)})`
                buttonIcon: "brightness_6"
                textWidth: 190
                value: root.m75LightingBrightness
                from: root.m75Number(root.m75FeatureRange("rgb", "brightness")?.min, 0)
                to: root.m75Number(root.m75FeatureRange("rgb", "brightness")?.max, 4)
                stopIndicatorValues: [0, 1, 2, 3, 4]
                usePercentTooltip: false
                onValueChanged: {
                    root.m75LightingBrightness = Math.round(value);
                    if (!root.m75Loading)
                        root.m75LightingDirty = true;
                }
            }

            ConfigSlider {
                text: `${Translation.tr("Animation speed")} (${Math.round(root.m75LightingSpeed)})`
                buttonIcon: "speed"
                textWidth: 190
                value: root.m75LightingSpeed
                from: root.m75Number(root.m75FeatureRange("rgb", "speed")?.min, 0)
                to: root.m75Number(root.m75FeatureRange("rgb", "speed")?.max, 4)
                stopIndicatorValues: [0, 1, 2, 3, 4]
                usePercentTooltip: false
                onValueChanged: {
                    root.m75LightingSpeed = Math.round(value);
                    if (!root.m75Loading)
                        root.m75LightingDirty = true;
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: Appearance.rounding.small
                    color: root.m75LightingColor
                    border.width: 1
                    border.color: Appearance.colors.colOutline
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("RGB color")
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            ConfigSlider {
                text: `${Translation.tr("Red")} (${root.m75LightingRed})`
                buttonIcon: "palette"
                textWidth: 190
                value: root.m75LightingRed
                from: 0
                to: 255
                usePercentTooltip: false
                onValueChanged: {
                    root.m75LightingRed = Math.round(value);
                    if (!root.m75Loading)
                        root.m75LightingDirty = true;
                }
            }

            ConfigSlider {
                text: `${Translation.tr("Green")} (${root.m75LightingGreen})`
                buttonIcon: "palette"
                textWidth: 190
                value: root.m75LightingGreen
                from: 0
                to: 255
                usePercentTooltip: false
                onValueChanged: {
                    root.m75LightingGreen = Math.round(value);
                    if (!root.m75Loading)
                        root.m75LightingDirty = true;
                }
            }

            ConfigSlider {
                text: `${Translation.tr("Blue")} (${root.m75LightingBlue})`
                buttonIcon: "palette"
                textWidth: 190
                value: root.m75LightingBlue
                from: 0
                to: 255
                usePercentTooltip: false
                onValueChanged: {
                    root.m75LightingBlue = Math.round(value);
                    if (!root.m75Loading)
                        root.m75LightingDirty = true;
                }
            }
        }

        ContentSubsection {
            visible: root.m75FeatureWritable("actuation")
            title: Translation.tr("Magnetic actuation")

            ConfigSlider {
                text: `${Translation.tr("Actuation distance")} (${root.rounded(root.m75ActuationMm, 2)} mm)`
                buttonIcon: "vertical_align_center"
                textWidth: 230
                value: root.m75ActuationMm
                from: root.m75Number(root.m75FeatureRange("actuation")?.min, 0.1)
                to: root.m75Number(root.m75FeatureRange("actuation")?.max, 3.2)
                usePercentTooltip: false
                onValueChanged: {
                    root.m75ActuationMm = root.m75RoundStep(value, root.m75FeatureRange("actuation")?.step ?? 0.01);
                    if (!root.m75Loading)
                        root.m75ActuationDirty = true;
                }
            }
        }

        ContentSubsection {
            visible: root.m75FeatureWritable("rapid_trigger")
            title: Translation.tr("Rapid Trigger")

            ConfigSwitch {
                buttonIcon: "bolt"
                text: Translation.tr("Enable Rapid Trigger")
                checked: root.m75RapidTriggerEnabled
                onCheckedChanged: {
                    root.m75RapidTriggerEnabled = checked;
                    if (!root.m75Loading)
                        root.m75RapidTriggerDirty = true;
                }
            }

            ConfigSlider {
                enabled: root.m75RapidTriggerEnabled
                text: `${Translation.tr("Trigger sensitivity")} (${root.rounded(root.m75RapidTriggerSensitivityMm, 2)} mm)`
                buttonIcon: "tune"
                textWidth: 230
                value: root.m75RapidTriggerSensitivityMm
                from: root.m75Number(root.m75FeatureRange("rapid_trigger")?.min, 0.1)
                to: root.m75Number(root.m75FeatureRange("rapid_trigger")?.max, 2)
                usePercentTooltip: false
                onValueChanged: {
                    root.m75RapidTriggerSensitivityMm = root.m75RoundStep(value, root.m75FeatureRange("rapid_trigger")?.step ?? 0.01);
                    if (!root.m75Loading)
                        root.m75RapidTriggerDirty = true;
                }
            }
        }

        RippleButtonWithIcon {
            visible: root.m75HasWritableSettings
            Layout.fillWidth: true
            enabled: MechlandsM75.connected
                && !MechlandsM75.actionRunning
                && (root.m75PollingDirty
                    || root.m75LightingDirty
                    || root.m75ActuationDirty
                    || root.m75RapidTriggerDirty)
            materialIcon: MechlandsM75.actionRunning ? "progress_activity" : "save"
            mainText: MechlandsM75.actionRunning ? Translation.tr("Applying keyboard settings") : Translation.tr("Apply keyboard settings")
            onClicked: root.applyM75Settings()
        }

        ContentSubsection {
            visible: MechlandsM75.features.length > 0
            title: Translation.tr("Driver capabilities")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: MechlandsM75.features

                    delegate: DeviceChip {
                        required property var modelData

                        icon: modelData.writable === true ? "tune" : "science"
                        label: modelData.label || modelData.id
                        detail: root.m75CapabilityDetail(modelData)
                    }
                }
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            enabled: !MechlandsM75.refreshing && !MechlandsM75.actionRunning
            materialIcon: MechlandsM75.refreshing ? "progress_activity" : "refresh"
            mainText: MechlandsM75.refreshing ? Translation.tr("Refreshing keyboard driver") : Translation.tr("Refresh keyboard driver")
            onClicked: MechlandsM75.refresh()
        }
    }

    ContentSection {
        icon: "mouse"
        title: Translation.tr("Logitech G502 X Plus")
        description: Translation.tr("Onboard profile, DPI and scroll wheel")

        DeviceChip {
            icon: LogitechG502.connected ? "mouse" : "mouse_lock"
            label: Translation.tr("Logitech G502 X Plus")
            detail: root.g502BatteryDetail()
        }

        StyledText {
            visible: !LogitechG502.solaarSupported
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: LogitechG502.solaarAvailable
                ? Translation.tr("Solaar cannot currently access this mouse. Battery status remains available from Linux.")
                : Translation.tr("Install Solaar to configure this mouse. Battery status remains available from Linux.")
        }

        StyledText {
            visible: LogitechG502.solaar?.cached === true
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Showing the latest Solaar settings cached for this mouse.")
        }

        StyledText {
            visible: LogitechG502.lastError.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            wrapMode: Text.Wrap
            color: Appearance.colors.colError
            text: LogitechG502.lastError
        }

        ContentSubsection {
            visible: LogitechG502.controlAvailable("onboard_profile")
            title: Translation.tr("Onboard profile")

            ConfigSelectionArray {
                currentValue: root.g502OnboardProfile
                options: root.g502ProfileOptions
                onSelected: newValue => root.g502OnboardProfile = `${newValue}`
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                enabled: LogitechG502.connected && !LogitechG502.actionRunning
                materialIcon: "save"
                mainText: Translation.tr("Apply onboard profile")
                onClicked: LogitechG502.set("onboard_profile", root.g502OnboardProfile)
            }
        }

        StyledText {
            visible: LogitechG502.controlAvailable("dpi") || LogitechG502.controlAvailable("report_rate")
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("DPI and report rate changes require the onboard profile to be Disabled. This page will never switch profiles automatically.")
        }

        ContentSubsection {
            visible: LogitechG502.controlAvailable("dpi")
            enabled: root.g502OnboardDisabled
            title: Translation.tr("Mouse sensitivity")

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "speed"
                    text: Translation.tr("DPI")
                    value: root.g502Dpi
                    from: 100
                    to: 25600
                    stepSize: 50
                    onValueChanged: root.g502Dpi = value
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    enabled: LogitechG502.connected && !LogitechG502.actionRunning
                    materialIcon: "save"
                    mainText: Translation.tr("Apply DPI")
                    onClicked: LogitechG502.set("dpi", root.g502Dpi)
                }
            }
        }

        ContentSubsection {
            visible: LogitechG502.controlAvailable("report_rate")
            enabled: root.g502OnboardDisabled
            title: Translation.tr("Report rate")

            ConfigSelectionArray {
                currentValue: root.g502ReportRate
                options: root.g502ReportRateOptions
                onSelected: newValue => root.g502ReportRate = `${newValue}`
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                enabled: LogitechG502.connected && !LogitechG502.actionRunning
                materialIcon: "save"
                mainText: Translation.tr("Apply report rate")
                onClicked: LogitechG502.set("report_rate", root.g502ReportRate)
            }
        }

        ContentSubsection {
            visible: LogitechG502.connected
            title: Translation.tr("Wheel event mode")

            ConfigSwitch {
                enabled: false
                buttonIcon: "mouse"
                text: Translation.tr("Multiple events per wheel notch")
                checked: false
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Disabled system-wide for this G502: applications receive one event per physical notch. Use Wheel speed above to control how far it moves.")
            }
        }

        ContentSubsection {
            visible: LogitechG502.controlAvailable("scroll_invert")
            title: Translation.tr("Wheel direction")

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "swap_vert"
                    text: Translation.tr("Invert wheel direction")
                    checked: root.g502InvertScroll
                    onCheckedChanged: root.g502InvertScroll = checked
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    enabled: LogitechG502.connected && !LogitechG502.actionRunning
                    materialIcon: "save"
                    mainText: Translation.tr("Apply wheel direction")
                    onClicked: LogitechG502.set("scroll_invert", root.g502InvertScroll ? "on" : "off")
                }
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            enabled: !LogitechG502.refreshing && !LogitechG502.actionRunning
            materialIcon: LogitechG502.refreshing ? "progress_activity" : "refresh"
            mainText: LogitechG502.refreshing ? Translation.tr("Refreshing Logitech mouse") : Translation.tr("Refresh Logitech mouse")
            onClicked: LogitechG502.refresh()
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Quickshell scrolling")
        description: Translation.tr("Scroll handling inside the shell interface")

        ConfigSwitch {
            buttonIcon: "touchpad_mouse"
            text: Translation.tr("Faster touchpad scroll")
            checked: Config.options.interactions.scrolling.fasterTouchpadScroll
            onCheckedChanged: Config.options.interactions.scrolling.fasterTouchpadScroll = checked
        }

        ConfigRow {
            uniform: true

            ConfigSpinBox {
                icon: "mouse"
                text: Translation.tr("Mouse scroll threshold")
                value: Config.options.interactions.scrolling.mouseScrollDeltaThreshold
                from: 1
                to: 1000
                stepSize: 5
                onValueChanged: Config.options.interactions.scrolling.mouseScrollDeltaThreshold = value
            }

            ConfigSpinBox {
                icon: "arrow_downward"
                text: Translation.tr("Mouse scroll factor")
                value: Config.options.interactions.scrolling.mouseScrollFactor
                from: 1
                to: 1000
                stepSize: 5
                onValueChanged: Config.options.interactions.scrolling.mouseScrollFactor = value
            }
        }

        ConfigSpinBox {
            icon: "touch_app"
            text: Translation.tr("Touchpad scroll factor")
            value: Config.options.interactions.scrolling.touchpadScrollFactor
            from: 1
            to: 2000
            stepSize: 10
            onValueChanged: Config.options.interactions.scrolling.touchpadScrollFactor = value
        }
    }

    ContentSection {
        visible: false
        icon: "devices"
        title: Translation.tr("Detected devices")

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "refresh"
                mainText: PeripheralSettings.refreshingDevices ? Translation.tr("Refreshing devices") : Translation.tr("Refresh devices")
                onClicked: PeripheralSettings.refreshDevices()
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reset all peripherals")
                onClicked: PeripheralSettings.resetAll()
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "save"
            mainText: Translation.tr("Apply all peripheral settings")
            onClicked: PeripheralSettings.applyAll()
        }

        StyledText {
            visible: root.deviceRows.length === 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("No physical input devices reported by Hyprland.")
        }

        ColumnLayout {
            visible: root.deviceRows.length > 0
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.deviceRows

                delegate: DeviceChip {
                    required property var modelData

                    icon: modelData.icon
                    label: modelData.label
                    detail: modelData.detail
                }
            }
        }
    }

    component DeviceChip: Rectangle {
        id: chip
        required property string icon
        required property string label
        property string detail: ""

        Layout.fillWidth: true
        implicitHeight: chipRow.implicitHeight + 18
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        RowLayout {
            id: chipRow
            anchors.fill: parent
            anchors.margins: 9
            spacing: 10

            MaterialSymbol {
                text: chip.icon
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: chip.label
                    elide: Text.ElideMiddle
                    color: Appearance.colors.colOnSecondaryContainer
                    font.weight: Font.Medium
                }

                StyledText {
                    visible: chip.detail.length > 0
                    Layout.fillWidth: true
                    text: chip.detail
                    elide: Text.ElideRight
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }
}
