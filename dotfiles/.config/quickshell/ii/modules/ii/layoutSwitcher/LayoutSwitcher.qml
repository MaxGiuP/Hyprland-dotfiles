import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool isOpen: false
    property string currentLayoutCommand: ""

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

    Loader {
        id: layoutSwitcherLoader
        // Keep the full-screen surface alive so its dim backdrop does not
        // animate its size whenever the picker is opened or closed.
        active: true

        sourceComponent: PanelWindow {
            id: panelWindow
            // Keep one fixed-size surface on the output. Opening and closing
            // only fades its contents; the backdrop never resizes.
            visible: true
            screen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:layoutSwitcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"
            // A transparent full-screen layer still receives pointer events.
            // Remove its input region entirely while the switcher is closed.
            mask: Region { item: root.isOpen ? backdrop : null }

            property int selectedIndex: 0

            function close() {
                root.isOpen = false;
            }

            function moveSelection(amount) {
                selectedIndex = (selectedIndex + amount + root.layouts.length) % root.layouts.length;
            }

            function applySelection() {
                Quickshell.execDetached([
                    "/home/linmax/.config/hypr/hyprland/scripts/select_layout.sh",
                    root.layouts[selectedIndex].command
                ]);
                close();
            }

            Rectangle {
                id: backdrop
                anchors.fill: parent
                // Match the overview/workspace-preview scrim instead of using
                // a hard black overlay.
                color: Appearance.colors.colScrim
                opacity: root.isOpen ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.isOpen
                onClicked: panelWindow.close()
            }

            Rectangle {
                id: content
                anchors.centerIn: parent
                width: 520
                height: listColumn.implicitHeight + 34
                // Use the same solid Material surface family as the workspace
                // preview, independent of the global transparency preference.
                color: Appearance.m3colors.m3surfaceContainer
                border.width: 1
                border.color: Appearance.m3colors.m3outlineVariant
                radius: Appearance.rounding.windowRounding
                focus: true
                opacity: root.isOpen ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.close();
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
                            color: selected
                                ? Appearance.m3colors.m3surfaceContainerHigh
                                : (current ? Appearance.m3colors.m3secondaryContainer : "transparent")
                            border.width: (selected || current) ? 1 : 0
                            border.color: current ? Appearance.colors.colPrimary : Appearance.m3colors.m3outlineVariant

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
                                color: Appearance.colors.colPrimary
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
                                color: Appearance.m3colors.m3onSurface
                                font.pixelSize: 31
                            }

                            MaterialSymbol {
                                anchors {
                                    left: parent.left
                                    leftMargin: 39
                                    verticalCenter: parent.verticalCenter
                                }
                                text: modelData.icon
                                color: Appearance.m3colors.m3onSurface
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
                                    color: current ? Appearance.colors.colPrimary : Appearance.m3colors.m3onSurface
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: modelData.description
                                    color: selected ? Appearance.m3colors.m3onSurface : Appearance.colors.colSubtext
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
                                color: Appearance.m3colors.m3surfaceContainerLow
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
                                        color: selected ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Component.onCompleted: Qt.callLater(() => content.forceActiveFocus())
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
        refreshCurrentLayout();
        root.isOpen = true;
    }

    function toggle() {
        if (root.isOpen) {
            root.isOpen = false;
        } else {
            open();
        }
    }

    IpcHandler {
        target: "layoutSwitcher"

        function open(): void { root.open(); }
        function close(): void { root.isOpen = false; }
        function toggle(): void { root.toggle(); }
    }

    GlobalShortcut {
        name: "layoutSwitcherToggle"
        description: "Choose window layout"
        onPressed: root.toggle()
    }
}
