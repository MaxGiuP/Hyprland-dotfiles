import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

FocusScope {
    id: root
    required property var scopeRoot
    focus: true

    readonly property var sessions: HyprlandData.windowList.filter(window => {
        const windowClass = `${window?.class ?? ""}`.toLowerCase();
        const title = `${window?.title ?? ""}`;
        const terminal = windowClass.indexOf("kitty") !== -1
            || windowClass.indexOf("foot") !== -1
            || windowClass.indexOf("alacritty") !== -1
            || windowClass.indexOf("wezterm") !== -1;
        return terminal && (title.indexOf(` | ${SystemInfo.username}`) !== -1
            || /(^|\s)(codex|claude code|gemini cli)(\s|$)/i.test(title));
    }).sort((left, right) => {
        const activityDifference = Number(root.isWorking(right)) - Number(root.isWorking(left));
        if (activityDifference !== 0)
            return activityDifference;
        const workspaceDifference = Number(left?.workspace?.id ?? 0) - Number(right?.workspace?.id ?? 0);
        if (workspaceDifference !== 0)
            return workspaceDifference;
        return root.cleanTitle(left).localeCompare(root.cleanTitle(right));
    })
    readonly property int workingCount: sessions.filter(session => root.isWorking(session)).length
    readonly property int waitingCount: Math.max(0, sessions.length - workingCount)

    function isWorking(session) {
        return /^[\u2800-\u28ff]/.test(`${session?.title ?? ""}`.trim());
    }

    function cleanTitle(session) {
        let title = `${session?.title ?? ""}`.trim();
        title = title.replace(/^[\u2800-\u28ff]\s*/, "");
        title = title.replace(/^([✓✔])\s*/, "");
        title = title.replace(/\s+\|\s+[^|]+$/, "");
        return title || Translation.tr("Untitled agent session");
    }

    function focusActiveItem() {
        if (sessionList.count > 0)
            sessionList.currentIndex = 0;
        else
            newSessionButton.forceActiveFocus();
    }

    function focusSession(session) {
        const address = `${session?.address ?? ""}`;
        if (!/^0x[0-9a-f]+$/i.test(address))
            return;
        Quickshell.execDetached([
            "hyprctl", "dispatch",
            `hl.dsp.focus({ window = "address:${address}" })`
        ]);
        if (!(scopeRoot?.pin ?? false))
            GlobalStates.closeSidebarLeft();
    }

    function launchCodex(resume) {
        const home = Quickshell.env("HOME") || "/home/linmax";
        const command = resume ? "codex resume" : "codex";
        Quickshell.execDetached([
            `${home}/.config/hypr/hyprland/scripts/launch_first_available.sh`,
            `kitty -1 ${command}`,
            `foot ${command}`,
            `alacritty -e ${command}`,
            `wezterm start -- ${command}`,
            `konsole -e ${command}`
        ]);
        if (!(scopeRoot?.pin ?? false))
            GlobalStates.closeSidebarLeft();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                implicitWidth: 44
                implicitHeight: 44
                radius: Appearance.rounding.small
                color: Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "robot_2"
                    iconSize: 25
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    text: Translation.tr("Agent desk")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: Translation.tr("Codex work across your desktop")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StatusCard {
                Layout.fillWidth: true
                icon: "progress_activity"
                label: Translation.tr("Working")
                value: root.workingCount
                accent: Appearance.colors.colPrimary
            }
            StatusCard {
                Layout.fillWidth: true
                icon: "task_alt"
                label: Translation.tr("Waiting")
                value: root.waitingCount
                accent: Appearance.colors.colSecondary
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Sessions")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: `${root.sessions.length}`
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        ListView {
            id: sessionList
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8
            clip: true
            model: ScriptModel { values: root.sessions }

            delegate: RippleButton {
                id: sessionButton
                required property var modelData
                width: ListView.view.width
                implicitHeight: 76
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.focusSession(modelData)

                contentItem: RowLayout {
                    spacing: 10

                    Rectangle {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: Appearance.rounding.full
                        color: ColorUtils.transparentize(
                            root.isWorking(sessionButton.modelData)
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSecondary,
                            0.82
                        )

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.isWorking(sessionButton.modelData)
                                ? "progress_activity"
                                : "terminal"
                            iconSize: 20
                            color: root.isWorking(sessionButton.modelData)
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSecondary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        StyledText {
                            Layout.fillWidth: true
                            text: root.cleanTitle(sessionButton.modelData)
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer2
                        }

                        RowLayout {
                            spacing: 5
                            MaterialSymbol {
                                text: "space_dashboard"
                                iconSize: 14
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: Translation.tr("Workspace %1").arg(sessionButton.modelData?.workspace?.id ?? "–")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            Rectangle {
                                implicitWidth: 4
                                implicitHeight: 4
                                radius: 2
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: root.isWorking(sessionButton.modelData)
                                    ? Translation.tr("Working")
                                    : Translation.tr("Ready")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: root.isWorking(sessionButton.modelData)
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSecondary
                            }
                        }
                    }

                    MaterialSymbol {
                        text: "arrow_outward"
                        iconSize: 17
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 }
            }

            displaced: Transition {
                NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic }
            }
        }

        ColumnLayout {
            visible: root.sessions.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignCenter
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "smart_toy"
                iconSize: 46
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("No Codex sessions open")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 250
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Translation.tr("Start one below and it will appear here automatically.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButtonWithIcon {
                id: newSessionButton
                Layout.fillWidth: true
                materialIcon: "add"
                mainText: Translation.tr("New session")
                onClicked: root.launchCodex(false)
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "history"
                mainText: Translation.tr("Resume")
                onClicked: root.launchCodex(true)
            }
        }
    }

    component StatusCard: Rectangle {
        required property string icon
        required property string label
        required property int value
        required property color accent
        implicitHeight: 62
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            MaterialSymbol {
                text: parent.parent.icon
                iconSize: 20
                color: parent.parent.accent
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: `${parent.parent.parent.value}`
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    text: parent.parent.parent.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
