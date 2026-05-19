import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)

    Loader {
        id: sessionLoader
        active: GlobalStates.sessionOpen
        onActiveChanged: {
            if (sessionLoader.active)
                SessionWarnings.refresh();
        }

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    GlobalStates.sessionOpen = false;
                }
            }
        }

        sourceComponent: PanelWindow { // Session menu
            id: sessionRoot
            visible: sessionLoader.active
            property string subtitle
            property var pendingSessionAction: null
            onVisibleChanged: {
                if (!visible)
                    resetSessionActionView();
            }

            function hide() {
                resetSessionActionView();
                GlobalStates.sessionOpen = false;
            }

            function resetSessionActionView() {
                sessionActionAnim.stop();
                pendingSessionAction = null;
                sessionActionIcon.opacity = 0;
                sessionActionIcon.scale = 1;
                contentColumn.opacity = 1;
                contentColumn.enabled = true;
                sessionMouseArea.enabled = true;
            }

            function runSessionAction(iconName, action, sourceItem) {
                if (sessionActionAnim.running)
                    return;

                pendingSessionAction = action;
                sessionActionIconSymbol.text = iconName;

                const point = sourceItem
                    ? sourceItem.mapToItem(sessionRoot.contentItem, sourceItem.width / 2, sourceItem.height / 2)
                    : Qt.point(sessionRoot.width / 2, sessionRoot.height + sessionActionIcon.width / 2);

                sessionActionIcon.x = point.x - sessionActionIcon.width / 2;
                sessionActionIcon.y = point.y - sessionActionIcon.height / 2;
                sessionActionIcon.scale = 0.55;
                sessionActionIcon.opacity = 1;
                contentColumn.enabled = false;
                sessionMouseArea.enabled = false;
                sessionActionAnim.restart();
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:session"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: ColorUtils.transparentize(Appearance.m3colors.m3background, Appearance.m3colors.darkmode ? 0.05 : 0.12)

            anchors {
                top: true
                left: true
                right: true
            }

            implicitWidth: root.focusedScreen?.width ?? 0
            implicitHeight: root.focusedScreen?.height ?? 0

            MouseArea {
                id: sessionMouseArea
                anchors.fill: parent
                onClicked: {
                    sessionRoot.hide();
                }
            }

            ColumnLayout { // Content column
                id: contentColumn
                anchors.centerIn: parent
                spacing: 15

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        sessionRoot.hide();
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 0
                    StyledText {
                        // Title
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.title
                            variableAxes: Appearance.font.variableAxes.title
                        }
                        text: Translation.tr("Session")
                    }

                    StyledText {
                        // Small instruction
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.normal
                        text: Translation.tr("Arrow keys to navigate, Enter to select\nEsc or click anywhere to cancel")
                    }
                }

                GridLayout {
                    columns: 4
                    columnSpacing: 15
                    rowSpacing: 15

                    SessionActionButton {
                        id: sessionLock
                        focus: sessionRoot.visible
                        buttonIcon: "lock"
                        buttonText: Translation.tr("Lock")
                        onClicked: {
                            sessionRoot.runSessionAction(buttonIcon, () => {
                                Session.lock();
                                sessionRoot.hide();
                            }, sessionLock);
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.right: sessionSleep
                        KeyNavigation.down: sessionHibernate
                    }
                    SessionActionButton {
                        id: sessionSleep
                        buttonIcon: "dark_mode"
                        buttonText: Translation.tr("Sleep")
                        onClicked: {
                            sessionRoot.runSessionAction(buttonIcon, () => {
                                Session.suspend();
                                sessionRoot.hide();
                            }, sessionSleep);
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionLock
                        KeyNavigation.right: sessionLogout
                        KeyNavigation.down: sessionShutdown
                    }
                    SessionActionButton {
                        id: sessionLogout
                        buttonIcon: "logout"
                        buttonText: Translation.tr("Logout")
                        onClicked: {
                            sessionRoot.runSessionAction(buttonIcon, () => {
                                Session.logout();
                                sessionRoot.hide();
                            }, sessionLogout);
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionSleep
                        KeyNavigation.right: sessionTaskManager
                        KeyNavigation.down: sessionReboot
                    }
                    SessionActionButton {
                        id: sessionTaskManager
                        buttonIcon: "browse_activity"
                        buttonText: Translation.tr("Task Manager")
                        onClicked: {
                            sessionRoot.runSessionAction(buttonIcon, () => {
                                Session.launchTaskManager();
                                sessionRoot.hide();
                            }, sessionTaskManager);
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionLogout
                        KeyNavigation.down: sessionFirmwareReboot
                    }

                    SessionActionButton {
                        id: sessionHibernate
                        buttonIcon: "downloading"
                        buttonText: Translation.tr("Hibernate")
                        onClicked: {
                            sessionRoot.runSessionAction(buttonIcon, () => {
                                Session.hibernate();
                                sessionRoot.hide();
                            }, sessionHibernate);
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.up: sessionLock
                        KeyNavigation.right: sessionShutdown
                    }
                    SessionActionButton {
                        id: sessionShutdown
                        buttonIcon: "power_settings_new"
                        buttonText: Translation.tr("Shutdown")
                        onClicked: {
                            sessionRoot.runSessionAction(buttonIcon, () => {
                                Session.poweroff();
                                sessionRoot.hide();
                            }, sessionShutdown);
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionHibernate
                        KeyNavigation.right: sessionReboot
                        KeyNavigation.up: sessionSleep
                    }
                    SessionActionButton {
                        id: sessionReboot
                        buttonIcon: "restart_alt"
                        buttonText: Translation.tr("Reboot")
                        onClicked: {
                            sessionRoot.runSessionAction(buttonIcon, () => {
                                Session.reboot();
                                sessionRoot.hide();
                            }, sessionReboot);
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionShutdown
                        KeyNavigation.right: sessionFirmwareReboot
                        KeyNavigation.up: sessionLogout
                    }
                    SessionActionButton {
                        id: sessionFirmwareReboot
                        buttonIcon: "settings_applications"
                        buttonText: Translation.tr("Reboot to firmware settings")
                        onClicked: {
                            sessionRoot.runSessionAction(buttonIcon, () => {
                                Session.rebootToFirmware();
                                sessionRoot.hide();
                            }, sessionFirmwareReboot);
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.up: sessionTaskManager
                        KeyNavigation.left: sessionReboot
                    }
                }

                DescriptionLabel {
                    Layout.alignment: Qt.AlignHCenter
                    text: sessionRoot.subtitle
                }
            }

            RowLayout {
                anchors {
                    top: contentColumn.bottom
                    topMargin: 10
                    horizontalCenter: contentColumn.horizontalCenter
                }
                spacing: 10

                Loader {
                    active: SessionWarnings.packageManagerRunning
                    visible: active
                    sourceComponent: DescriptionLabel {
                        text: Translation.tr("Your package manager is running")
                        textColor: Appearance.m3colors.m3onErrorContainer
                        color: Appearance.m3colors.m3errorContainer
                    }
                }
                Loader {
                    active: SessionWarnings.downloadRunning
                    visible: active
                    sourceComponent: DescriptionLabel {
                        text: Translation.tr("There might be a download in progress")
                        textColor: Appearance.m3colors.m3onErrorContainer
                        color: Appearance.m3colors.m3errorContainer
                    }
                }
            }

            Item {
                id: sessionActionIcon
                z: 100
                width: 120
                height: 120
                opacity: 0
                visible: opacity > 0

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Appearance.colors.colPrimary
                }

                MaterialSymbol {
                    id: sessionActionIconSymbol
                    anchors.centerIn: parent
                    iconSize: 60
                    fill: 1
                    color: Appearance.colors.colOnPrimary
                }
            }

            SequentialAnimation {
                id: sessionActionAnim

                ParallelAnimation {
                    NumberAnimation {
                        target: contentColumn; property: "opacity"
                        to: 0; duration: 180; easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: sessionActionIcon; property: "x"
                        to: (sessionRoot.width - sessionActionIcon.width) / 2
                        duration: 650; easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: sessionActionIcon; property: "y"
                        to: (sessionRoot.height - sessionActionIcon.height) / 2
                        duration: 650; easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: sessionActionIcon; property: "scale"
                        to: 1.0; duration: 650; easing.type: Easing.OutCubic
                    }
                }

                PauseAnimation { duration: 140 }

                ScriptAction {
                    script: {
                        const action = sessionRoot.pendingSessionAction;
                        sessionRoot.pendingSessionAction = null;
                        if (action)
                            action();
                    }
                }
            }
        }
    }

    component DescriptionLabel: Rectangle {
        id: descriptionLabel
        property string text
        property color textColor: Appearance.colors.colOnTooltip
        color: Appearance.colors.colTooltip
        clip: true
        radius: Appearance.rounding.normal
        implicitHeight: descriptionLabelText.implicitHeight + 10 * 2
        implicitWidth: descriptionLabelText.implicitWidth + 15 * 2

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        StyledText {
            id: descriptionLabelText
            anchors.centerIn: parent
            color: descriptionLabel.textColor
            text: descriptionLabel.text
        }
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }

        function close(): void {
            GlobalStates.sessionOpen = false;
        }

        function open(): void {
            GlobalStates.sessionOpen = true;
        }
    }

    GlobalShortcut {
        name: "sessionToggle"
        description: "Toggles session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }
    }

    GlobalShortcut {
        name: "sessionOpen"
        description: "Opens session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = true;
        }
    }

    GlobalShortcut {
        name: "sessionClose"
        description: "Closes session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = false;
        }
    }
}
