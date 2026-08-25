import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

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
            name: "Master", command: "master", icon: "view_sidebar",
            description: "Primary pane with a stack",
            preview: [
                { x: 0.00, y: 0.00, w: 0.62, h: 1.00 },
                { x: 0.66, y: 0.00, w: 0.34, h: 0.46 },
                { x: 0.66, y: 0.50, w: 0.34, h: 0.50 }
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
        active: false

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: layoutSwitcherLoader.active
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
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            property int selectedIndex: 0

            function close() {
                layoutSwitcherLoader.active = false;
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
                anchors.fill: parent
                // Keep the switcher legible even when the shell's content
                // transparency is enabled.
                color: "#A6000000"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: panelWindow.close()
            }

            Rectangle {
                id: content
                anchors.centerIn: parent
                width: 520
                height: listColumn.implicitHeight + 34
                color: Appearance.m3colors.m3surfaceContainerHigh
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.windowRounding
                focus: true

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
                            width: listColumn.width
                            height: 76
                            radius: Appearance.rounding.small
                            color: selected ? Appearance.colors.colPrimaryContainer : "transparent"
                            border.width: selected ? 1 : 0
                            border.color: Appearance.colors.colPrimary

                            Behavior on color { ColorAnimation { duration: 100 } }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: panelWindow.selectedIndex = index
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
                                color: Appearance.colors.colOnPrimaryContainer
                                font.pixelSize: 31
                            }

                            MaterialSymbol {
                                anchors {
                                    left: parent.left
                                    leftMargin: 39
                                    verticalCenter: parent.verticalCenter
                                }
                                text: modelData.icon
                                color: selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0
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
                                    color: selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: modelData.description
                                    color: selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
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
                                color: Appearance.colors.colLayer1
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

    function open() {
        layoutSwitcherLoader.active = true;
    }

    function toggle() {
        if (layoutSwitcherLoader.active) {
            layoutSwitcherLoader.active = false;
        } else {
            open();
        }
    }

    IpcHandler {
        target: "layoutSwitcher"

        function open(): void { root.open(); }
        function close(): void { layoutSwitcherLoader.active = false; }
        function toggle(): void { root.toggle(); }
    }

    GlobalShortcut {
        name: "layoutSwitcherToggle"
        description: "Choose window layout"
        onPressed: root.toggle()
    }
}
