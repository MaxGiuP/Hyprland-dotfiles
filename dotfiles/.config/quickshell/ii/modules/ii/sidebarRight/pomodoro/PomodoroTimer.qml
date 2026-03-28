import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property bool showSettingsDialog: false
    property int draftFocusSeconds: Config.options.time.pomodoro.focus
    property int draftBreakSeconds: Config.options.time.pomodoro.breakTime
    property int draftLongBreakSeconds: Config.options.time.pomodoro.longBreak
    property int draftCycles: 4

    function normalizeTimerSeconds(seconds, fallbackSeconds) {
        const parsed = parseInt(seconds);
        if (!isNaN(parsed) && parsed >= 0) return parsed;
        return fallbackSeconds;
    }

    function loadDraftFromConfig() {
        root.draftFocusSeconds = normalizeTimerSeconds(Config.options.time.pomodoro.focus, 25 * 60);
        root.draftBreakSeconds = normalizeTimerSeconds(Config.options.time.pomodoro.breakTime, 5 * 60);
        root.draftLongBreakSeconds = normalizeTimerSeconds(Config.options.time.pomodoro.longBreak, 15 * 60);
        root.draftCycles = Math.max(1, parseInt(Config.options.time.pomodoro.cyclesBeforeLongBreak) || 4);
    }

    implicitHeight: Math.max(contentColumn.implicitHeight, root.showSettingsDialog ? dialog.implicitHeight + 36 : 0)
    implicitWidth: contentColumn.implicitWidth

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        CircularProgress {
            Layout.alignment: Qt.AlignHCenter
            lineWidth: 8
            value: TimerService.pomodoroSecondsLeft / TimerService.pomodoroLapDuration
            implicitSize: 200
            enableAnimation: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        let minutes = Math.floor(TimerService.pomodoroSecondsLeft / 60).toString().padStart(2, '0');
                        let seconds = Math.floor(TimerService.pomodoroSecondsLeft % 60).toString().padStart(2, '0');
                        return `${minutes}:${seconds}`;
                    }
                    font.pixelSize: 40
                    color: Appearance.m3colors.m3onSurface
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: TimerService.pomodoroLongBreak ? Translation.tr("Long break") : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }

        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            RippleButton {
                implicitHeight: 35
                implicitWidth: 40
                onClicked: {
                    root.loadDraftFromConfig();
                    root.showSettingsDialog = true;
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "tune"
                    color: Appearance.colors.colOnLayer2
                }
            }

            RippleButton {
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: TimerService.pomodoroRunning ? Translation.tr("Pause") : (TimerService.pomodoroSecondsLeft === TimerService.focusTime) ? Translation.tr("Start") : Translation.tr("Resume")
                    color: TimerService.pomodoroRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                }
                implicitHeight: 35
                implicitWidth: 90
                font.pixelSize: Appearance.font.pixelSize.larger
                onClicked: TimerService.togglePomodoro()
                colBackground: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
                colBackgroundHover: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
            }

            RippleButton {
                implicitHeight: 35
                implicitWidth: 90
                onClicked: TimerService.resetPomodoro()
                enabled: (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration) || TimerService.pomodoroCycle > 0 || TimerService.pomodoroBreak
                font.pixelSize: Appearance.font.pixelSize.larger
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive

                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Reset")
                    color: Appearance.colors.colOnErrorContainer
                }
            }
        }
    }

    Item {
        anchors.fill: parent
        z: 999
        visible: root.showSettingsDialog

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                propagateComposedEvents: false
                onClicked: root.showSettingsDialog = false
            }
        }

        Rectangle {
            id: dialog
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 12
            implicitWidth: Math.min(parent.width - 24, 360)
            radius: Appearance.rounding.normal
            color: Qt.rgba(Appearance.colors.colLayer0.r, Appearance.colors.colLayer0.g, Appearance.colors.colLayer0.b, 0.98)
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            implicitHeight: settingsColumn.implicitHeight + 24

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                preventStealing: true
                onWheel: wheel.accepted = true
            }

            ColumnLayout {
                id: settingsColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Pomodoro settings")
                    font.pixelSize: Appearance.font.pixelSize.large
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Layout.alignment: Qt.AlignTop

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                text: Translation.tr("Focus")
                                Layout.alignment: Qt.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }

                            StyledSpinBox {
                                Layout.alignment: Qt.AlignVCenter
                                from: 1
                                to: 240
                                value: Math.max(1, Math.round(root.draftFocusSeconds / 60))
                                onValueModified: root.draftFocusSeconds = value * 60
                            }

                            StyledText {
                                text: Translation.tr("min")
                                Layout.alignment: Qt.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }

                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                text: Translation.tr("Short break")
                                Layout.alignment: Qt.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }

                            StyledSpinBox {
                                Layout.alignment: Qt.AlignVCenter
                                from: 1
                                to: 120
                                value: Math.max(1, Math.round(root.draftBreakSeconds / 60))
                                onValueModified: root.draftBreakSeconds = value * 60
                            }

                            StyledText {
                                text: Translation.tr("min")
                                Layout.alignment: Qt.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }

                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                text: Translation.tr("Long break")
                                Layout.alignment: Qt.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }

                            StyledSpinBox {
                                Layout.alignment: Qt.AlignVCenter
                                from: 1
                                to: 180
                                value: Math.max(1, Math.round(root.draftLongBreakSeconds / 60))
                                onValueModified: root.draftLongBreakSeconds = value * 60
                            }

                            StyledText {
                                text: Translation.tr("min")
                                Layout.alignment: Qt.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }

                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                text: Translation.tr("Cycles")
                                Layout.alignment: Qt.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }

                            StyledSpinBox {
                                Layout.fillWidth: true
                                from: 1
                                to: 12
                                value: root.draftCycles
                                onValueModified: root.draftCycles = value
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Item { Layout.fillWidth: true }

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        padding: 8
                        onClicked: root.showSettingsDialog = false
                    }
                    DialogButton {
                        buttonText: Translation.tr("Save")
                        padding: 8
                        onClicked: {
                            Config.options.time.pomodoro.focus = Math.max(1, root.draftFocusSeconds);
                            Config.options.time.pomodoro.breakTime = Math.max(1, root.draftBreakSeconds);
                            Config.options.time.pomodoro.longBreak = Math.max(1, root.draftLongBreakSeconds);
                            Config.options.time.pomodoro.cyclesBeforeLongBreak = Math.max(1, root.draftCycles);
                            Qt.callLater(TimerService.resetPomodoro);
                            root.showSettingsDialog = false;
                        }
                    }
                }
            }
        }
    }
}
