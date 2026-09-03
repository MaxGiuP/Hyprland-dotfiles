import QtQuick
import QtQuick.Layouts
import Quickshell
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
    property bool draftsInitialized: false
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

    function syncMonitorDrafts(force = false) {
        if (draftsInitialized && !force)
            return;
        const nextDrafts = {};
        for (const mon of HyprlandData.monitors) {
            const existing = root.monitorDrafts[mon.name];
            nextDrafts[mon.name] = {
                x: existing?.x ?? mon.x,
                y: existing?.y ?? mon.y,
                scale: existing?.scale ?? mon.scale,
                transform: existing?.transform ?? mon.transform
            };
        }
        root.monitorDrafts = nextDrafts;
        root.draftsInitialized = true;
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
        return (draft.transform % 2 === 1) ? mon.height : mon.width;
    }

    function draftHeight(mon) {
        const draft = root.monitorDraft(mon);
        return (draft.transform % 2 === 1) ? mon.width : mon.height;
    }

    function updateMonitorPosition(mon, x, y) {
        const draft = root.monitorDraft(mon);
        draft.x = Math.round(x / 10) * 10;
        draft.y = Math.round(y / 10) * 10;
        root.monitorDrafts = Object.assign({}, root.monitorDrafts);
    }

    function monitorCommand(mon, transform) {
        const draft = root.monitorDraft(mon);
        const refresh = Number(mon.refreshRate || 60).toFixed(2);
        const scale = Number(draft.scale || mon.scale || 1).toFixed(2);
        return `${mon.name},${mon.width}x${mon.height}@${refresh},${Math.round(draft.x)}x${Math.round(draft.y)},${scale},transform,${transform}`;
    }

    function applyMonitorTransform(mon, transform) {
        const draft = root.monitorDraft(mon);
        draft.transform = transform;
        root.monitorDrafts = Object.assign({}, root.monitorDrafts);
        Quickshell.execDetached(["hyprctl", "keyword", "monitor", root.monitorCommand(mon, transform)]);
    }

    function applyMonitorLayout(mon) {
        Quickshell.execDetached(["hyprctl", "keyword", "monitor", root.monitorCommand(mon, root.monitorDraft(mon).transform)]);
    }

    function applyAllMonitorLayouts() {
        for (const mon of HyprlandData.monitors)
            root.applyMonitorLayout(mon);
    }

    Component.onCompleted: syncMonitorDrafts(true)

    Connections {
        target: HyprlandData
        function onMonitorsChanged() {
            root.syncMonitorDrafts(true);
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

                    width: Math.max(90, root.draftWidth(modelData) * layoutCanvas.scaleFactor)
                    height: Math.max(70, root.draftHeight(modelData) * layoutCanvas.scaleFactor)
                    radius: Appearance.rounding.normal
                    color: modelData.focused ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                    border.width: 2
                    border.color: modelData.focused ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                    Binding {
                        target: monitorCard
                        property: "x"
                        when: !dragArea.drag.active
                        value: root.layoutPadding + (root.monitorDraft(modelData).x - root.layoutMinX) * layoutCanvas.scaleFactor
                    }

                    Binding {
                        target: monitorCard
                        property: "y"
                        when: !dragArea.drag.active
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
                            text: `${root.draftWidth(modelData)}x${root.draftHeight(modelData)}`
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        drag.target: parent
                        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                        onReleased: {
                            root.updateMonitorPosition(
                                modelData,
                                ((monitorCard.x - root.layoutPadding) / layoutCanvas.scaleFactor) + root.layoutMinX,
                                ((monitorCard.y - root.layoutPadding) / layoutCanvas.scaleFactor) + root.layoutMinY
                            );
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
                onClicked: root.applyAllMonitorLayouts()
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reset from current state")
                onClicked: root.syncMonitorDrafts(true)
            }
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
                        textRole: "text"
                        model: root.orientationOptions
                        currentIndex: Math.max(0, root.orientationOptions.findIndex(option => option.value === root.monitorDraft(modelData).transform))
                        onActivated: index => root.applyMonitorTransform(modelData, root.orientationOptions[index].value)
                    }

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "save"
                        mainText: Translation.tr("Apply this monitor")
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
