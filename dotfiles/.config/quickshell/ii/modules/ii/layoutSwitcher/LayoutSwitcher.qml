import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common.functions

Scope {
    id: root
    readonly property bool isOpen: GlobalStates.layoutSwitcherOpen
    property string currentLayoutCommand: ""
    property string targetScreenName: ""
    readonly property var targetScreen: Quickshell.screens.find(screen => screen.name === targetScreenName)
                                        ?? Quickshell.screens[0]
                                        ?? null
    // Slight translucency for the small dialog card behind the entries.
    readonly property real frostedOpacity: 0.65

    function prepareTargetScreen() {
        const focusedName = HyprlandData.monitors.find(monitor => monitor.focused)?.name
                            || HyprlandData.eventFocusedMonitorName
                            || Hyprland.focusedMonitor?.name
                            || "";
        const focusedScreen = Quickshell.screens.find(screen => screen.name === focusedName);
        root.targetScreenName = (focusedScreen ?? Quickshell.screens[0] ?? null)?.name ?? "";
    }

    readonly property var layouts: [
        {
            name: "Dwindle", command: "dwindle", icon: "account_tree",
            description: "Adaptive split tree",
            preview: [
                { x: 0.00, y: 0.00, w: 0.58, h: 1.00 },
                { x: 0.62, y: 0.00, w: 0.38, h: 0.46 },
                { x: 0.62, y: 0.50, w: 0.38, h: 0.50 }
            ]
        },
        {
            name: "Dwindle Columns", command: "dwindle-columns", icon: "vertical_split",
            description: "Always split windows side by side",
            preview: [
                { x: 0.00, y: 0.00, w: 0.30, h: 1.00 },
                { x: 0.34, y: 0.00, w: 0.30, h: 1.00 },
                { x: 0.68, y: 0.00, w: 0.32, h: 1.00 }
            ]
        },
        {
            name: "Dwindle Rows", command: "dwindle-rows", icon: "splitscreen",
            description: "Always split windows above and below",
            preview: [
                { x: 0.00, y: 0.00, w: 1.00, h: 0.30 },
                { x: 0.00, y: 0.34, w: 1.00, h: 0.30 },
                { x: 0.00, y: 0.68, w: 1.00, h: 0.32 }
            ]
        },
        {
            name: "Master", command: "master", icon: "view_sidebar",
            description: "Primary pane with a stack",
            preview: [
                { x: 0.00, y: 0.00, w: 0.62, h: 1.00 },
                { x: 0.66, y: 0.00, w: 0.34, h: 0.46 },
                { x: 0.66, y: 0.50, w: 0.34, h: 0.50 }
            ]
        },
        {
            name: "Top Master", command: "master-top", icon: "view_agenda",
            description: "Primary pane above a lower stack",
            preview: [
                { x: 0.00, y: 0.00, w: 1.00, h: 0.58 },
                { x: 0.00, y: 0.62, w: 0.46, h: 0.38 },
                { x: 0.50, y: 0.62, w: 0.50, h: 0.38 }
            ]
        },
        {
            name: "Center Master", command: "master-center", icon: "view_column",
            description: "Primary pane centered between stacks",
            preview: [
                { x: 0.00, y: 0.00, w: 0.22, h: 1.00 },
                { x: 0.26, y: 0.00, w: 0.48, h: 1.00 },
                { x: 0.78, y: 0.00, w: 0.22, h: 1.00 }
            ]
        },
        {
            name: "Scroller", command: "scroller", icon: "view_column_2",
            description: "Horizontal scrolling columns",
            preview: [
                { x: 0.00, y: 0.00, w: 0.46, h: 1.00 },
                { x: 0.50, y: 0.00, w: 0.46, h: 1.00 },
                { x: 1.00, y: 0.00, w: 0.30, h: 1.00 }
            ]
        },
        {
            name: "Monocle", command: "monocle", icon: "crop_16_9",
            description: "Focus the active window",
            preview: [ { x: 0.00, y: 0.00, w: 1.00, h: 1.00 } ]
        }
    ]

    // The visual-only dimming surface follows the monitor that was focused
    // when the selector opened and leaves pointer handling to the compositor.
    PanelWindow {
        id: dimWindow
        visible: root.isOpen
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:layoutSwitcherDim"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: Qt.rgba(0, 0, 0, 0.42)
        mask: Region {}
    }

    Loader {
        id: layoutSwitcherLoader
        // Keep the component loaded, but unmap its Wayland surface while closed
        // so it cannot leave an invisible pointer-input region behind.
        active: true

        sourceComponent: PanelWindow {
            id: panelWindow
            // This surface is only the dialog card, so Hyprland blurs the card
            // rather than the full-screen dimming layer.
            visible: root.isOpen
            screen: root.targetScreen

            anchors { top: true; left: true }
            margins {
                top: Math.round((screen?.height - implicitHeight) / 2)
                left: Math.round((screen?.width - implicitWidth) / 2)
            }
            implicitWidth: 520
            implicitHeight: listColumn.implicitHeight + 34

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:layoutSwitcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"
            mask: Region { item: root.isOpen ? content : null }

            property int selectedIndex: 0

            function syncFocusGrab() {
                GlobalFocusGrab.removeDismissable(panelWindow);
                if (root.isOpen)
                    GlobalFocusGrab.addDismissable(panelWindow);
            }

            function dismiss() {
                GlobalStates.layoutSwitcherOpen = false;
            }

            function moveSelection(amount) {
                selectedIndex = (selectedIndex + amount + root.layouts.length) % root.layouts.length;
            }

            function applySelection() {
                Quickshell.execDetached([
                    "/home/linmax/.config/hypr/hyprland/scripts/select_layout.sh",
                    root.layouts[selectedIndex].command
                ]);
                dismiss();
            }

            Item {
                id: content
                anchors.fill: parent
                focus: true
                opacity: root.isOpen ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                }

                // The small box behind the layout entries. This feeds the
                // dialog-only blur layer and never alters the desktop cover.
                Rectangle {
                    id: dialogBackground
                    anchors.fill: parent
                    color: ColorUtils.applyAlpha(Appearance.colors.colLayer0Base, root.frostedOpacity)
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    radius: Appearance.rounding.windowRounding
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.dismiss();
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
                        panelWindow.moveSelection(-1);
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
                        panelWindow.moveSelection(1);
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        panelWindow.applySelection();
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Column {
                    id: listColumn
                    anchors {
                        fill: parent
                        margins: 17
                    }
                    spacing: 8

                    Text {
                        text: "Choose layout"
                        color: Appearance.colors.colOnLayer0
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.title
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: "Arrow keys to select · Enter to apply · Esc to cancel"
                        color: Appearance.colors.colSubtext
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    Item { width: 1; height: 5 }

                    Repeater {
                        model: root.layouts

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool selected: index === panelWindow.selectedIndex
                            readonly property bool current: modelData.command === root.currentLayoutCommand
                            width: listColumn.width
                            height: 76
                            radius: Appearance.rounding.small
                            color: current
                                ? ColorUtils.applyAlpha(Appearance.colors.colLayer1Base, 0.94)
                                : (selected
                                    ? ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 0.08)
                                    : "transparent")
                            border.width: (selected || current) ? 1 : 0
                            border.color: current ? Appearance.colors.colOutline : Appearance.colors.colLayer0Border

                            Behavior on color { ColorAnimation { duration: 100 } }

                            Rectangle {
                                anchors {
                                    left: parent.left
                                    leftMargin: 5
                                    verticalCenter: parent.verticalCenter
                                }
                                width: 4
                                height: 36
                                radius: width / 2
                                color: Appearance.colors.colOutline
                                visible: current
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: panelWindow.selectedIndex = index
                                onPositionChanged: panelWindow.selectedIndex = index
                                onClicked: panelWindow.applySelection()
                            }

                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 12
                                    verticalCenter: parent.verticalCenter
                                }
                                width: 24
                                text: "›"
                                visible: selected
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: 31
                            }

                            MaterialSymbol {
                                anchors {
                                    left: parent.left
                                    leftMargin: 39
                                    verticalCenter: parent.verticalCenter
                                }
                                text: modelData.icon
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: 25
                            }

                            Column {
                                anchors {
                                    left: parent.left
                                    leftMargin: 78
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 3

                                Text {
                                    text: modelData.name
                                    color: Appearance.colors.colOnLayer0
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: modelData.description
                                    color: selected ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }

                            Rectangle {
                                id: preview
                                anchors {
                                    right: parent.right
                                    rightMargin: 14
                                    verticalCenter: parent.verticalCenter
                                }
                                width: 105
                                height: 52
                                radius: 7
                                color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.12)
                                clip: true

                                Repeater {
                                    model: modelData.preview
                                    delegate: Rectangle {
                                        required property var modelData
                                        x: modelData.x * preview.width + 3
                                        y: modelData.y * preview.height + 3
                                        width: modelData.w * preview.width - 6
                                        height: modelData.h * preview.height - 6
                                        radius: 4
                                        color: current
                                            ? Appearance.colors.colOutline
                                            : (selected ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            onVisibleChanged: syncFocusGrab()

            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (root.isOpen)
                        GlobalStates.layoutSwitcherOpen = false;
                }
            }

            Component.onCompleted: {
                syncFocusGrab();
                Qt.callLater(() => content.forceActiveFocus());
            }
            Component.onDestruction: GlobalFocusGrab.removeDismissable(panelWindow)
        }
    }

    Process {
        id: currentLayoutProcess
        command: ["/home/linmax/.config/hypr/hyprland/scripts/current_layout.sh"]

        stdout: StdioCollector {
            id: currentLayoutCollector
            onStreamFinished: {
                const command = currentLayoutCollector.text.trim();
                const index = root.layouts.findIndex(layout => layout.command === command);
                if (index < 0)
                    return;

                root.currentLayoutCommand = command;
                layoutSwitcherLoader.item.selectedIndex = index;
            }
        }
    }

    function refreshCurrentLayout() {
        if (!currentLayoutProcess.running)
            currentLayoutProcess.running = true;
    }

    function open() {
        prepareTargetScreen();
        refreshCurrentLayout();
        GlobalStates.layoutSwitcherOpen = true;
    }

    function toggle() {
        if (root.isOpen) {
            GlobalStates.layoutSwitcherOpen = false;
        } else {
            open();
        }
    }

    IpcHandler {
        target: "layoutSwitcher"

        function open(): void { root.open(); }
        function close(): void { GlobalStates.layoutSwitcherOpen = false; }
        function toggle(): void { root.toggle(); }
    }

    GlobalShortcut {
        name: "layoutSwitcherToggle"
        description: "Choose window layout"
        onPressed: root.toggle()
    }
}
