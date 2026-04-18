import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    title: "Terminal"
    showCenterButton: true
    minimumWidth: 460
    minimumHeight: 280

    readonly property bool isRunning: shellProcess.running

    // Command history (up/down arrow navigation)
    property var cmdHistory: []
    property int historyIndex: -1

    function addLine(text, lineType) {
        outputModel.append({ lineText: text, lineType: lineType })
        Qt.callLater(() => outputListView.positionViewAtEnd())
    }

    function runCommand(cmd) {
        const trimmed = (cmd ?? "").trim()
        if (!trimmed || root.isRunning) return
        addLine("$ " + trimmed, "cmd")
        if (root.cmdHistory.length === 0 || root.cmdHistory[root.cmdHistory.length - 1] !== trimmed)
            root.cmdHistory = root.cmdHistory.concat([trimmed])
        root.historyIndex = -1
        commandInput.text = ""
        shellProcess.command = ["bash", "-c", trimmed]
        shellProcess.running = true
    }

    ListModel { id: outputModel }

    Process {
        id: shellProcess
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.addLine(data, "stdout")
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => root.addLine(data, "stderr")
        }
        onExited: code => {
            if (code !== 0)
                root.addLine("[process exited " + code + "]", "info")
        }
    }

    contentItem: OverlayBackground {
        radius: root.contentRadius

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Toolbar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: toolbarRow.implicitHeight + 8
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: toolbarRow
                    anchors { fill: parent; leftMargin: 4; rightMargin: 4; topMargin: 4; bottomMargin: 4 }
                    spacing: 4

                    // Update button — opens kitty with paru -Syu for full interactive output
                    RippleButton {
                        buttonRadius: height / 2
                        colBackground: Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        onClicked: Quickshell.execDetached(["kitty", "--title", "System Update", "paru", "-Syu"])
                        contentItem: Row {
                            anchors.centerIn: parent
                            leftPadding: 10
                            rightPadding: 10
                            spacing: 4
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "system_update_alt"
                                iconSize: 16
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Update"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                        StyledToolTip { text: "Run paru -Syu in kitty" }
                    }

                    Item { Layout.fillWidth: true }

                    // Kill button (only visible while a command is running)
                    RippleButton {
                        visible: root.isRunning
                        buttonRadius: height / 2
                        implicitWidth: implicitHeight
                        colBackground: Appearance.colors.colErrorContainer
                        colBackgroundHover: Appearance.colors.colErrorContainerHover
                        colRipple: Appearance.colors.colErrorContainerActive
                        onClicked: shellProcess.running = false
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "stop_circle"
                            iconSize: 20
                            color: Appearance.colors.colOnErrorContainer
                        }
                        StyledToolTip { text: "Kill process" }
                    }

                    // Clear button
                    RippleButton {
                        buttonRadius: height / 2
                        implicitWidth: implicitHeight
                        colBackground: Appearance.colors.colLayer3
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        colRipple: Appearance.colors.colLayer3Active
                        onClicked: outputModel.clear()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "delete_sweep"
                            iconSize: 20
                        }
                        StyledToolTip { text: "Clear output" }
                    }
                }
            }

            // Output area
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLowest
                clip: true

                ListView {
                    id: outputListView
                    anchors { fill: parent; margins: 6 }
                    model: outputModel
                    clip: true
                    spacing: 1
                    ScrollBar.vertical: StyledScrollBar {}

                    delegate: Text {
                        required property string lineText
                        required property string lineType
                        width: outputListView.width - 12
                        text: lineText
                        wrapMode: Text.WrapAnywhere
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        renderType: Text.NativeRendering
                        color: {
                            switch (lineType) {
                                case "stderr": return Appearance.colors.colError
                                case "cmd":    return Appearance.colors.colPrimary
                                case "info":   return Appearance.colors.colSubtext
                                default:       return Appearance.colors.colOnLayer1
                            }
                        }
                    }

                    StyledText {
                        visible: outputModel.count === 0
                        anchors.centerIn: parent
                        text: "No output yet. Type a command below or click Update."
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }

            // Input bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: inputRow.implicitHeight + 8
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: inputRow
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 4; bottomMargin: 4 }
                    spacing: 6

                    StyledText {
                        text: "$"
                        color: Appearance.colors.colPrimary
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: commandInput.implicitHeight + 6
                        color: Appearance.colors.colLayer1Base
                        radius: Appearance.rounding.small

                        StyledTextInput {
                            id: commandInput
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10; topMargin: 3; bottomMargin: 3 }
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.small
                            enabled: !root.isRunning
                            selectByMouse: true

                            Keys.onReturnPressed: root.runCommand(commandInput.text)
                            Keys.onEnterPressed: root.runCommand(commandInput.text)
                            Keys.onUpPressed: {
                                if (root.cmdHistory.length === 0) return
                                const newIdx = root.historyIndex < 0
                                    ? root.cmdHistory.length - 1
                                    : Math.max(0, root.historyIndex - 1)
                                root.historyIndex = newIdx
                                commandInput.text = root.cmdHistory[newIdx]
                                commandInput.cursorPosition = commandInput.text.length
                            }
                            Keys.onDownPressed: {
                                if (root.historyIndex < 0) return
                                const newIdx = root.historyIndex + 1
                                if (newIdx >= root.cmdHistory.length) {
                                    root.historyIndex = -1
                                    commandInput.text = ""
                                } else {
                                    root.historyIndex = newIdx
                                    commandInput.text = root.cmdHistory[newIdx]
                                    commandInput.cursorPosition = commandInput.text.length
                                }
                            }
                        }
                    }

                    RippleButton {
                        buttonRadius: height / 2
                        implicitWidth: implicitHeight
                        enabled: !root.isRunning
                        colBackground: Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        onClicked: root.runCommand(commandInput.text)
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "play_arrow"
                            iconSize: 20
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        StyledToolTip { text: "Run (Enter)" }
                    }
                }
            }
        }
    }
}
