import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF
import qs.modules.common.widgets
import qs.modules.ii.overlay
import QMLTermWidget 2.0

StyledOverlayWidget {
    id: root
    title: "Terminal"
    showCenterButton: true
    useOpacityMaskLayer: false
    minimumWidth: 520
    minimumHeight: 320

    property bool terminalReady: false

    function focusTerminal() {
        if (term)
            term.forceActiveFocus()
    }

    function runCommand(cmd) {
        OverlayTerminal.runCommand(cmd)
        Qt.callLater(root.focusTerminal)
    }

    function runUpdateScript() {
        root.runCommand(`'${CF.StringUtils.shellSingleQuoteEscape(Updates.updateScriptPath)}'`)
    }

    function consumePendingOverlayCommand() {
        if (OverlayTerminal.consumePendingOverlayCommand(
                Updates.pendingOverlayCommandNonce,
                Updates.pendingOverlayCommand
            )) {
            Updates.pendingOverlayCommand = ""
            Updates.pendingOverlayCommandLabel = ""
        }
    }

    contentItem: OverlayBackground {
        radius: root.contentRadius

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: toolbarRow.implicitHeight + 8
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: toolbarRow
                    anchors { fill: parent; leftMargin: 4; rightMargin: 4; topMargin: 4; bottomMargin: 4 }
                    spacing: 4

                    RippleButton {
                        buttonRadius: height / 2
                        colBackground: Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        onClicked: root.runUpdateScript()
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
                        StyledToolTip { text: "Run the update script here" }
                    }

                    Item { Layout.fillWidth: true }

                    RippleButton {
                        buttonRadius: height / 2
                        implicitWidth: implicitHeight
                        colBackground: Appearance.colors.colErrorContainer
                        colBackgroundHover: Appearance.colors.colErrorContainerHover
                        colRipple: Appearance.colors.colErrorContainerActive
                        onClicked: {
                            if (root.terminalReady)
                                OverlayTerminal.sendRaw("\u0003")
                            Qt.callLater(root.focusTerminal)
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "stop_circle"
                            iconSize: 20
                            color: Appearance.colors.colOnErrorContainer
                        }
                        StyledToolTip { text: "Send Ctrl+C" }
                    }

                    RippleButton {
                        buttonRadius: height / 2
                        implicitWidth: implicitHeight
                        colBackground: Appearance.colors.colLayer3
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        colRipple: Appearance.colors.colLayer3Active
                        onClicked: {
                            if (root.terminalReady)
                                OverlayTerminal.clearTerminal()
                            Qt.callLater(root.focusTerminal)
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "delete_sweep"
                            iconSize: 20
                        }
                        StyledToolTip { text: "Clear terminal" }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLowest
                clip: true

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: root.focusTerminal()
                }

                Rectangle {
                    anchors.fill: parent
                    visible: !root.terminalReady
                    color: Appearance.colors.colLayer2

                    Column {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "terminal"
                            iconSize: 24
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            text: "Loading terminal..."
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }

                QMLTermWidget {
                    id: term
                    anchors.fill: parent
                    anchors.margins: 1
                    focus: true
                    activeFocusOnTab: true
                    font.family: "Noto Sans Mono"
                    font.pointSize: 11
                    colorScheme: "BreezeModified"
                    session: OverlayTerminal.session

                    onImagePainted: {
                        root.terminalReady = true
                        OverlayTerminal.displayReady = true
                        OverlayTerminal.flushQueuedCommands()
                    }

                    Component.onCompleted: {
                        OverlayTerminal.ensureStarted()
                        OverlayTerminal.displayReady = root.terminalReady
                        Qt.callLater(root.focusTerminal)
                        Qt.callLater(root.consumePendingOverlayCommand)
                    }

                    Component.onDestruction: OverlayTerminal.displayReady = false
                }

                Loader {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 4
                    active: root.terminalReady
                    sourceComponent: QMLTermScrollbar {
                        terminal: term

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Appearance.colors.colPrimary
                            opacity: parent.opacity
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: OverlayTerminal

        function onSessionChanged() {
            root.terminalReady = false
        }
    }

    Connections {
        target: Updates

        function onPendingOverlayCommandNonceChanged() {
            root.consumePendingOverlayCommand()
        }
    }
}
