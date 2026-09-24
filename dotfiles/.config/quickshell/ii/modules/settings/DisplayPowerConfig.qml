import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760
    property int currentSubTab: 0
    readonly property var tabs: [
        { name: Translation.tr("Displays"), icon: "desktop_windows" },
        { name: Translation.tr("Colour & night light"), icon: "routine" },
        { name: Translation.tr("Power"), icon: "battery_android_full" }
    ]

    function applySubTab(subTab, sectionId = "") {
        root.currentSubTab = Math.max(0, Math.min(subTab, root.tabs.length - 1))
        root.contentY = 0
    }

    property var monitorDrafts: ({})
    property string monitorApplyMessage: ""
    property bool monitorApplyFailed: false
    property real layoutPadding: 20
    readonly property var orientationOptions: [
        { text: Translation.tr("Normal"), value: 0 },
        { text: Translation.tr("90°"), value: 1 },
        { text: Translation.tr("180°"), value: 2 },
        { text: Translation.tr("270°"), value: 3 },
        { text: Translation.tr("Flipped"), value: 4 },
        { text: Translation.tr("Flipped 90°"), value: 5 },
        { text: Translation.tr("Flipped 180°"), value: 6 },
        { text: Translation.tr("Flipped 270°"), value: 7 }
    ]
    readonly property real layoutMinX: {
        const monitors = HyprlandData.monitors;
        if (!monitors || monitors.length === 0)
            return 0;
        return Math.min(...monitors.map(mon => root.monitorDraft(mon).x));
    }
    readonly property real layoutMinY: {
        const monitors = HyprlandData.monitors;
        if (!monitors || monitors.length === 0)
            return 0;
        return Math.min(...monitors.map(mon => root.monitorDraft(mon).y));
    }
    readonly property real layoutMaxX: {
        const monitors = HyprlandData.monitors;
        if (!monitors || monitors.length === 0)
            return 1;
        return Math.max(...monitors.map(mon => root.monitorDraft(mon).x + root.draftWidth(mon)));
    }
    readonly property real layoutMaxY: {
        const monitors = HyprlandData.monitors;
        if (!monitors || monitors.length === 0)
            return 1;
        return Math.max(...monitors.map(mon => root.monitorDraft(mon).y + root.draftHeight(mon)));
    }
    readonly property real layoutSpanWidth: Math.max(1, layoutMaxX - layoutMinX)
    readonly property real layoutSpanHeight: Math.max(1, layoutMaxY - layoutMinY)

    function syncMonitorDrafts(reset = false) {
        const nextDrafts = {};
        for (const mon of HyprlandData.monitors) {
            const existing = root.monitorDrafts[mon.name];
            const matchesCurrent = existing && existing.x === mon.x && existing.y === mon.y
                && existing.scale === mon.scale && existing.transform === mon.transform;
            nextDrafts[mon.name] = !reset && existing?.dirty && !matchesCurrent ? existing : {
                x: mon.x,
                y: mon.y,
                scale: mon.scale,
                transform: mon.transform,
                dirty: false
            };
        }
        root.monitorDrafts = nextDrafts;
    }

    function monitorDraft(mon) {
        return root.monitorDrafts[mon.name] ?? {
            x: mon.x,
            y: mon.y,
            scale: mon.scale,
            transform: mon.transform
        };
    }

    function draftWidth(mon) {
        const draft = root.monitorDraft(mon);
        return ((draft.transform % 2 === 1) ? mon.height : mon.width) / draft.scale;
    }

    function draftHeight(mon) {
        const draft = root.monitorDraft(mon);
        return ((draft.transform % 2 === 1) ? mon.width : mon.height) / draft.scale;
    }

    function snapMonitorPosition(mon, x, y, distance) {
        const width = root.draftWidth(mon);
        const height = root.draftHeight(mon);
        let snappedX = Math.round(x / 10) * 10;
        let snappedY = Math.round(y / 10) * 10;
        let nearestX = distance;
        let nearestY = distance;

        for (const other of HyprlandData.monitors) {
            if (other.name === mon.name)
                continue;
            const draft = root.monitorDraft(other);
            const right = draft.x + root.draftWidth(other);
            const bottom = draft.y + root.draftHeight(other);

            // Only align edges of nearby displays. Use logical dimensions so
            // scaled and rotated monitors meet at the same desktop coordinate.
            if (y <= bottom + distance && y + height >= draft.y - distance) {
                for (const edge of [draft.x - width, right, draft.x, right - width]) {
                    const delta = Math.abs(x - edge);
                    if (delta <= nearestX) {
                        snappedX = edge;
                        nearestX = delta;
                    }
                }
            }
            if (x <= right + distance && x + width >= draft.x - distance) {
                for (const edge of [draft.y - height, bottom, draft.y, bottom - height]) {
                    const delta = Math.abs(y - edge);
                    if (delta <= nearestY) {
                        snappedY = edge;
                        nearestY = delta;
                    }
                }
            }
        }
        return { x: Math.round(snappedX), y: Math.round(snappedY) };
    }

    function updateMonitorPosition(mon, x, y, snapDistance = 0) {
        const position = root.snapMonitorPosition(mon, x, y, snapDistance);
        root.monitorDrafts = Object.assign({}, root.monitorDrafts, {
            [mon.name]: Object.assign({}, root.monitorDraft(mon), {
                x: position.x,
                y: position.y,
                dirty: true
            })
        });
        root.monitorApplyMessage = "";
    }

    function monitorCommand(mon) {
        const draft = root.monitorDraft(mon);
        const refresh = Number(mon.refreshRate || 60).toFixed(2);
        const scale = Number(draft.scale || mon.scale || 1);
        return `hl.monitor({ output = ${JSON.stringify(mon.name)}, mode = "${mon.width}x${mon.height}@${refresh}", position = "${Math.round(draft.x)}x${Math.round(draft.y)}", scale = ${scale}, transform = ${draft.transform} })`;
    }

    function applyMonitorTransform(mon, transform) {
        root.monitorDrafts = Object.assign({}, root.monitorDrafts, {
            [mon.name]: Object.assign({}, root.monitorDraft(mon), { transform: transform, dirty: true })
        });
        root.applyMonitorLayout(mon);
    }

    function applyMonitorLayout(mon) {
        root.applyMonitorLayouts([mon]);
    }

    function applyAllMonitorLayouts() {
        root.applyMonitorLayouts(HyprlandData.monitors);
    }

    function applyMonitorLayouts(monitors) {
        if (monitorApplyProc.running || monitors.length === 0)
            return;
        root.monitorApplyFailed = false;
        root.monitorApplyMessage = Translation.tr("Applying monitor positions…");
        // Lua configurations reject the legacy `hyprctl keyword monitor` API.
        // Submit the whole layout together so individual monitor updates cannot race.
        monitorApplyProc.command = ["hyprctl", "eval", monitors.map(mon => root.monitorCommand(mon)).join("\n")];
        monitorApplyProc.running = true;
    }

    Process {
        id: monitorApplyProc
        stdout: StdioCollector { id: monitorApplyOutput }
        stderr: StdioCollector { id: monitorApplyErrors }
        onExited: (exitCode, exitStatus) => {
            // hyprctl can return exit code zero even when its reply is an error.
            root.monitorApplyFailed = exitCode !== 0 || exitStatus !== 0 || monitorApplyOutput.text.trim() !== "ok";
            root.monitorApplyMessage = root.monitorApplyFailed
                ? Translation.tr("Could not apply monitor positions") + ": "
                    + (monitorApplyErrors.text.trim() || monitorApplyOutput.text.trim() || String(exitCode))
                : Translation.tr("Monitor positions applied");
            monitorRefreshTimer.restart();
        }
    }

    Timer {
        id: monitorRefreshTimer
        interval: 250
        onTriggered: HyprlandData.updateMonitors()
    }

    Component.onCompleted: syncMonitorDrafts(true)

    Connections {
        target: HyprlandData
        function onMonitorsChanged() {
            root.syncMonitorDrafts();
        }
    }

    SecondaryTabBar {
        Layout.fillWidth: true
        currentIndex: root.currentSubTab
        onCurrentIndexChanged: {
            root.currentSubTab = currentIndex
            root.contentY = 0
        }

        Repeater {
            model: root.tabs
            delegate: SecondaryTabButton {
                required property var modelData
                buttonIcon: modelData.icon
                buttonText: modelData.name
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 0
        icon: "brightness_6"
        title: Translation.tr("Display")

        Rectangle {
            id: layoutCanvas
            Layout.fillWidth: true
            Layout.preferredHeight: 380
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1
            clip: true

            property real usableWidth: width - root.layoutPadding * 2
            property real usableHeight: height - root.layoutPadding * 2
            property real scaleFactor: Math.min(
                usableWidth / root.layoutSpanWidth,
                usableHeight / root.layoutSpanHeight
            )

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Appearance.colors.colLayer1 }
                    GradientStop { position: 1.0; color: Appearance.colors.colLayer2 }
                }
            }

            Repeater {
                model: HyprlandData.monitors

                delegate: Rectangle {
                    id: monitorCard
                    required property var modelData
                    property bool dragging: false

                    width: Math.max(90, root.draftWidth(modelData) * layoutCanvas.scaleFactor)
                    height: Math.max(70, root.draftHeight(modelData) * layoutCanvas.scaleFactor)
                    radius: Appearance.rounding.normal
                    color: modelData.focused ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                    border.width: 2
                    border.color: modelData.focused ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                    Binding {
                        target: monitorCard
                        property: "x"
                        when: !monitorCard.dragging
                        restoreMode: Binding.RestoreNone
                        value: root.layoutPadding + (root.monitorDraft(modelData).x - root.layoutMinX) * layoutCanvas.scaleFactor
                    }

                    Binding {
                        target: monitorCard
                        property: "y"
                        when: !monitorCard.dragging
                        restoreMode: Binding.RestoreNone
                        value: root.layoutPadding + (root.monitorDraft(modelData).y - root.layoutMinY) * layoutCanvas.scaleFactor
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        StyledText {
                            Layout.fillWidth: true
                            color: modelData.focused ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                            text: modelData.name
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            color: modelData.focused ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: `${Math.round(root.draftWidth(modelData))}x${Math.round(root.draftHeight(modelData))}`
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        enabled: !monitorApplyProc.running
                        preventStealing: true
                        drag.target: monitorCard
                        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property real grabX: 0
                        property real grabY: 0

                        onPressed: mouse => {
                            grabX = mouse.x;
                            grabY = mouse.y;
                            monitorCard.dragging = true;
                        }
                        onCanceled: monitorCard.dragging = false
                        onPositionChanged: mouse => {
                            if (!drag.active)
                                return;
                            const pointer = mapToItem(layoutCanvas, mouse.x, mouse.y);
                            const position = root.snapMonitorPosition(
                                modelData,
                                (pointer.x - grabX - root.layoutPadding) / layoutCanvas.scaleFactor + root.layoutMinX,
                                (pointer.y - grabY - root.layoutPadding) / layoutCanvas.scaleFactor + root.layoutMinY,
                                12 / layoutCanvas.scaleFactor
                            );
                            monitorCard.x = root.layoutPadding + (position.x - root.layoutMinX) * layoutCanvas.scaleFactor;
                            monitorCard.y = root.layoutPadding + (position.y - root.layoutMinY) * layoutCanvas.scaleFactor;
                        }
                        onReleased: {
                            if (drag.active) {
                                root.updateMonitorPosition(
                                    modelData,
                                    ((monitorCard.x - root.layoutPadding) / layoutCanvas.scaleFactor) + root.layoutMinX,
                                    ((monitorCard.y - root.layoutPadding) / layoutCanvas.scaleFactor) + root.layoutMinY,
                                    12 / layoutCanvas.scaleFactor
                                );
                            }
                            // Commit the drop before restoring the position bindings.
                            monitorCard.dragging = false;
                        }
                    }
                }
            }
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "save"
                mainText: Translation.tr("Apply all monitor positions")
                enabled: !monitorApplyProc.running && HyprlandData.monitors.length > 0
                onClicked: root.applyAllMonitorLayouts()
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reset from current state")
                enabled: !monitorApplyProc.running
                onClicked: {
                    root.monitorApplyMessage = "";
                    root.syncMonitorDrafts(true);
                    HyprlandData.updateMonitors();
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.monitorApplyMessage.length > 0
            text: root.monitorApplyMessage
            color: root.monitorApplyFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        Repeater {
            model: Brightness.monitors

            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    Layout.leftMargin: 8
                    color: Appearance.colors.colOnSecondaryContainer
                    text: modelData.screen?.name ?? Translation.tr("Display")
                }

                StyledSlider {
                    from: 0
                    to: 1
                    value: modelData.brightness ?? 0
                    enabled: modelData.ready
                    configuration: StyledSlider.Configuration.M
                    usePercentTooltip: false
                    tooltipContent: `${Math.round((value ?? 0) * 100)}%`
                    onMoved: modelData.setBrightness(value)
                }
            }
        }

        Repeater {
            model: HyprlandData.monitors

            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.leftMargin: 8
                    color: Appearance.colors.colOnSecondaryContainer
                    text: `${modelData.name} • ${modelData.width}x${modelData.height} @ ${Math.round(modelData.refreshRate)}Hz`
                }

                StyledText {
                    Layout.leftMargin: 8
                    color: Appearance.colors.colSubtext
                    text: `${Translation.tr("Position")}: ${root.monitorDraft(modelData).x}, ${root.monitorDraft(modelData).y} • ${Translation.tr("Scale")}: ${root.monitorDraft(modelData).scale} • ${Translation.tr("Transform")}: ${root.monitorDraft(modelData).transform}`
                }

                ConfigRow {
                    uniform: true

                    StyledComboBox {
                        Layout.fillWidth: true
                        buttonIcon: "screen_rotation"
                        enabled: !monitorApplyProc.running
                        textRole: "text"
                        model: root.orientationOptions
                        currentIndex: Math.max(0, root.orientationOptions.findIndex(option => option.value === root.monitorDraft(modelData).transform))
                        onActivated: index => root.applyMonitorTransform(modelData, root.orientationOptions[index].value)
                    }

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "save"
                        mainText: Translation.tr("Apply this monitor")
                        enabled: !monitorApplyProc.running
                        onClicked: root.applyMonitorLayout(modelData)
                    }
                }
            }
        }

        ConfigRow {
            uniform: true
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "brightness_low"
                mainText: Translation.tr("Dim")
                onClicked: Brightness.decreaseBrightness()
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "brightness_high"
                mainText: Translation.tr("Brighten")
                onClicked: Brightness.increaseBrightness()
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "developer_board"
                mainText: Translation.tr("Reload Hyprland")
                onClicked: Quickshell.execDetached(["hyprctl", "reload"])
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 1
        icon: "routine"
        title: Translation.tr("Color & Night Light")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: Hyprsunset.active ? "bedtime" : "routine"
                text: Translation.tr("Night light")
                checked: Hyprsunset.active
                onClicked: Hyprsunset.toggle()
            }
            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("Automatic schedule")
                checked: Config.options.light.night.automatic
                onCheckedChanged: Config.options.light.night.automatic = checked
            }
        }

        ConfigSpinBox {
            icon: "thermostat"
            text: Translation.tr("Color temperature")
            value: Config.options.light.night.colorTemperature
            from: 1000
            to: 10000
            stepSize: 100
            onValueChanged: Config.options.light.night.colorTemperature = value
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Night light start time (HH:mm)")
            text: Config.options.light.night.from
            wrapMode: TextEdit.NoWrap
            onTextChanged: Config.options.light.night.from = text
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Night light end time (HH:mm)")
            text: Config.options.light.night.to
            wrapMode: TextEdit.NoWrap
            onTextChanged: Config.options.light.night.to = text
        }

        ConfigSwitch {
            buttonIcon: "flare"
            text: Translation.tr("Anti-flashbang")
            checked: Config.options.light.antiFlashbang.enable
            onCheckedChanged: Config.options.light.antiFlashbang.enable = checked
        }
    }

    ContentSection {
        visible: root.currentSubTab === 2
        icon: "battery_android_full"
        title: Translation.tr("Power")

        ContentSubsection {
            title: Translation.tr("Power mode")

            ConfigSelectionArray {
                currentValue: PowerProfiles.profile
                onSelected: newValue => PowerProfiles.profile = newValue
                options: [
                    { displayName: Translation.tr("Power saver"), icon: "energy_savings_leaf", value: PowerProfile.PowerSaver },
                    { displayName: Translation.tr("Balanced"), icon: "balance", value: PowerProfile.Balanced },
                    { displayName: Translation.tr("Performance"), icon: "speed", value: PowerProfile.Performance }
                ].filter(option => option.value !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)
            }

            StyledText {
                visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                Layout.fillWidth: true
                color: Appearance.colors.colError
                text: Translation.tr("Performance is currently limited by the system.")
                wrapMode: Text.Wrap
            }
        }

        StyledText {
            Layout.leftMargin: 8
            color: Appearance.colors.colOnSecondaryContainer
            text: Battery.available
                ? Translation.tr("%1% • %2").arg(Math.round(Battery.percentage * 100)).arg(Battery.isCharging ? Translation.tr("Charging") : Translation.tr("On battery"))
                : Translation.tr("No battery detected")
        }

        StyledText {
            Layout.leftMargin: 8
            color: Appearance.colors.colSubtext
            visible: Battery.available
            text: Battery.health > 0
                ? Translation.tr("Health: %1%").arg(Math.round(Battery.health))
                : ""
        }

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "warning"
                text: Translation.tr("Low battery")
                value: Config.options.battery.low
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: Config.options.battery.low = value
            }
            ConfigSpinBox {
                icon: "dangerous"
                text: Translation.tr("Critical battery")
                value: Config.options.battery.critical
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: Config.options.battery.critical = value
            }
        }

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "pause"
                text: Translation.tr("Suspend at")
                value: Config.options.battery.suspend
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: Config.options.battery.suspend = value
            }
            ConfigSpinBox {
                icon: "charger"
                text: Translation.tr("Full battery")
                value: Config.options.battery.full
                from: 0
                to: 101
                stepSize: 1
                onValueChanged: Config.options.battery.full = value
            }
        }

        ConfigSwitch {
            buttonIcon: "bedtime"
            text: Translation.tr("Automatic suspend on low battery")
            checked: Config.options.battery.automaticSuspend
            onCheckedChanged: Config.options.battery.automaticSuspend = checked
        }
    }

}
