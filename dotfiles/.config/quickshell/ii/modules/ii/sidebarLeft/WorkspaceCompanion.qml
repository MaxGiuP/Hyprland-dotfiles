import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

FocusScope {
    id: root
    required property var scopeRoot
    focus: true

    readonly property string monitorName: `${scopeRoot?.attachedScreenName ?? ""}`
    readonly property int workspaceId: {
        const eventId = Number(HyprlandData.activeWorkspaceIdsByMonitor[monitorName] ?? 0);
        if (eventId > 0)
            return eventId;
        const monitor = HyprlandData.monitors.find(item => item?.name === monitorName);
        const monitorId = Number(monitor?.activeWorkspace?.id ?? 0);
        if (monitorId > 0)
            return monitorId;
        return Number(HyprlandData.activeWorkspace?.id ?? 0);
    }
    readonly property string workspaceKey: workspaceId > 0 ? `${workspaceId}` : "unknown"
    readonly property var workspaceWindows: HyprlandData.windowList.filter(window =>
        Number(window?.workspace?.id ?? 0) === root.workspaceId
        && Number(window?.mapped ?? 1) !== 0
    )
    property string loadedWorkspaceKey: ""
    property bool loadingNote: false

    function notesByWorkspace() {
        try {
            return JSON.parse(Persistent.states.sidebar.workspaceNotesJson || "{}");
        } catch (error) {
            return {};
        }
    }

    function saveNote() {
        if (!Persistent.ready || root.loadingNote || !root.loadedWorkspaceKey)
            return;
        const notes = root.notesByWorkspace();
        const content = noteInput.text;
        if (content.length > 0)
            notes[root.loadedWorkspaceKey] = content;
        else
            delete notes[root.loadedWorkspaceKey];
        Persistent.states.sidebar.workspaceNotesJson = JSON.stringify(notes);
    }

    function loadNote() {
        saveDebounce.stop();
        root.saveNote();
        root.loadingNote = true;
        root.loadedWorkspaceKey = root.workspaceKey;
        noteInput.text = root.notesByWorkspace()[root.workspaceKey] ?? "";
        root.loadingNote = false;
    }

    function focusActiveItem() {
        noteInput.forceActiveFocus();
    }

    function run(command) {
        Quickshell.execDetached(command);
    }

    function launchFromSystem(action) {
        const home = Quickshell.env("HOME") || "/home/linmax";
        if (action === "terminal")
            run([`${home}/.config/hypr/hyprland/scripts/launch_first_available.sh`, "kitty -1", "foot", "alacritty", "wezterm", "konsole", "xterm"]);
        else if (action === "files")
            run([`${home}/.config/hypr/hyprland/scripts/launch_first_available.sh`, "dolphin", "org.kde.dolphin", "nautilus --new-window", "thunar", "kitty -1 fish -c yazi"]);
    }

    function focusWindow(window) {
        const address = `${window?.address ?? ""}`;
        if (!address)
            return;
        run(["hyprctl", "dispatch", `hl.dsp.focus({ window = "address:${address}" })`]);
        if (!(scopeRoot?.pin ?? false))
            GlobalStates.closeSidebarLeft();
    }

    Component.onCompleted: loadNote()
    onWorkspaceKeyChanged: loadNote()

    Timer {
        id: saveDebounce
        interval: 350
        onTriggered: root.saveNote()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                implicitWidth: 42
                implicitHeight: 42
                radius: Appearance.rounding.small
                color: Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "space_dashboard"
                    iconSize: 23
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    text: root.workspaceId > 0
                        ? Translation.tr("Workspace %1").arg(root.workspaceId)
                        : Translation.tr("Current workspace")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: root.workspaceWindows.length === 1
                        ? Translation.tr("1 open app")
                        : Translation.tr("%1 open apps").arg(root.workspaceWindows.length)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "terminal"
                mainText: Translation.tr("Terminal")
                onClicked: root.launchFromSystem("terminal")
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "folder"
                mainText: Translation.tr("Files")
                onClicked: root.launchFromSystem("files")
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "content_paste"
                mainText: Translation.tr("Clipboard")
                onClicked: root.run(["hyprctl", "dispatch", "hl.dsp.global(\"quickshell:overviewClipboardToggle\")"])
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "screenshot_region"
                mainText: Translation.tr("Screenshot")
                onClicked: root.run(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"])
            }
        }

        ColumnLayout {
            visible: root.workspaceWindows.length > 0
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                text: Translation.tr("Open here")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colSubtext
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 176)
                spacing: 5
                clip: true
                model: ScriptModel { values: root.workspaceWindows }

                delegate: RippleButton {
                    id: windowButton
                    required property var modelData
                    width: ListView.view.width
                    implicitHeight: 38
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    onClicked: root.focusWindow(modelData)

                    contentItem: RowLayout {
                        spacing: 9
                        MaterialSymbol {
                            text: "web_asset"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: `${windowButton.modelData?.title ?? windowButton.modelData?.class ?? Translation.tr("Window")}`
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: `${windowButton.modelData?.class ?? ""}`
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MaterialSymbol {
                            text: "arrow_forward"
                            iconSize: 16
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }

        StyledText {
            text: Translation.tr("Workspace scratchpad")
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colSubtext
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 130
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            border.width: noteInput.activeFocus ? 2 : 1
            border.color: noteInput.activeFocus
                ? Appearance.colors.colPrimary
                : Appearance.colors.colLayer3

            ScrollView {
                anchors.fill: parent
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                StyledTextArea {
                    id: noteInput
                    width: parent.width
                    placeholderText: Translation.tr("Keep notes, links, commands or reminders for this workspace…")
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    selectByMouse: true
                    persistentSelection: true
                    background: null
                    padding: 12
                    onTextChanged: if (!root.loadingNote) saveDebounce.restart()
                }
            }
        }
    }
}
