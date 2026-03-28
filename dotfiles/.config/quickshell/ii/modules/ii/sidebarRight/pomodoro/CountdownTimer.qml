import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property bool showSettingsDialog: false
    property int draftCountdownSeconds: Math.max(1, TimerService.countdownDuration)

    readonly property int progressValue: Math.max(0, TimerService.countdownSecondsLeft)
    readonly property int totalValue: Math.max(1, TimerService.countdownDuration)

    function formatSeconds(totalSeconds) {
        const safeSeconds = Math.max(0, Math.floor(totalSeconds));
        const hours = Math.floor(safeSeconds / 3600);
        const minutes = Math.floor((safeSeconds % 3600) / 60);
        const seconds = safeSeconds % 60;
        if (hours > 0) {
            return `${hours.toString().padStart(2, "0")}:${minutes.toString().padStart(2, "0")}:${seconds.toString().padStart(2, "0")}`;
        }
        return `${minutes.toString().padStart(2, "0")}:${seconds.toString().padStart(2, "0")}`;
    }

    function syncDialFromDraft() {
        if (!dialPicker) return;
        dialPicker.hourValue = Math.floor(root.draftCountdownSeconds / 3600);
        dialPicker.minuteValue = Math.floor((root.draftCountdownSeconds % 3600) / 60);
        dialPicker.secondValue = root.draftCountdownSeconds % 60;
    }

    implicitWidth: contentColumn.implicitWidth
    implicitHeight: Math.max(contentColumn.implicitHeight, root.showSettingsDialog ? dialog.implicitHeight + 36 : 0)

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        CircularProgress {
            Layout.alignment: Qt.AlignHCenter
            lineWidth: 8
            value: root.progressValue / root.totalValue
            implicitSize: 200
            enableAnimation: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.formatSeconds(TimerService.countdownSecondsLeft)
                    font.pixelSize: 40
                    color: Appearance.m3colors.m3onSurface
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: TimerService.countdownRunning ? Translation.tr("Running") : Translation.tr("Ready")
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
                    root.draftCountdownSeconds = Math.max(1, TimerService.countdownDuration);
                    root.syncDialFromDraft();
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
                    text: TimerService.countdownRunning
                        ? Translation.tr("Pause")
                        : TimerService.countdownSecondsLeft === TimerService.countdownDuration || TimerService.countdownSecondsLeft === 0
                            ? Translation.tr("Start")
                            : Translation.tr("Resume")
                    color: TimerService.countdownRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                }
                implicitHeight: 35
                implicitWidth: 90
                font.pixelSize: Appearance.font.pixelSize.larger
                onClicked: TimerService.toggleCountdown()
                colBackground: TimerService.countdownRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
                colBackgroundHover: TimerService.countdownRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
            }

            RippleButton {
                implicitHeight: 35
                implicitWidth: 90
                onClicked: TimerService.resetCountdown()
                enabled: TimerService.countdownRunning || TimerService.countdownSecondsLeft < TimerService.countdownDuration
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
            implicitWidth: Math.min(parent.width - 24, 320)
            radius: Appearance.rounding.normal
            color: Qt.rgba(Appearance.colors.colLayer0.r, Appearance.colors.colLayer0.g, Appearance.colors.colLayer0.b, 0.98)
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            implicitHeight: settingsColumn.implicitHeight + 24

            ColumnLayout {
                id: settingsColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Countdown")
                    font.pixelSize: Appearance.font.pixelSize.large
                }

                TimeDialPicker {
                    id: dialPicker
                    Layout.alignment: Qt.AlignHCenter
                    onValuesChanged: (hourValue, minuteValue, secondValue) => {
                        root.draftCountdownSeconds = Math.max(1, hourValue * 3600 + minuteValue * 60 + secondValue);
                    }
                    Component.onCompleted: root.syncDialFromDraft()
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            {"name": "05:00", "seconds": 5 * 60},
                            {"name": "15:00", "seconds": 15 * 60},
                            {"name": "30:00", "seconds": 30 * 60}
                        ]
                        delegate: GroupButton {
                            required property var modelData
                            Layout.fillWidth: true
                            buttonRadius: Appearance.rounding.small
                            onClicked: {
                                root.draftCountdownSeconds = modelData.seconds;
                                root.syncDialFromDraft();
                            }
                            contentItem: StyledText {
                                anchors.centerIn: parent
                                text: modelData.name
                                color: Appearance.colors.colOnLayer2
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
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
                            TimerService.setCountdownDuration(root.draftCountdownSeconds);
                            root.showSettingsDialog = false;
                        }
                    }
                }
            }
        }
    }
}
