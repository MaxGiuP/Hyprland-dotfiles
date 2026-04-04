import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import QMLTermWidget 2.0

FocusScope {
    id: root
    focus: true
    activeFocusOnTab: true

    property int currentTerminalIndex: 0
    property int terminalCounter: 0

    function currentTerminalItem() {
        return terminalRepeater.itemAt(root.currentTerminalIndex);
    }

    function focusTerminal() {
        const item = root.currentTerminalItem();
        if (item && item.term)
            item.term.forceActiveFocus();
    }

    function addTerminal(workingDirectory) {
        terminalCounter += 1;
        terminalTabs.append({
            "label": `fish ${terminalCounter}`,
            "workingDirectory": workingDirectory || (Quickshell.env("HOME") || "/")
        });
        currentTerminalIndex = terminalTabs.count - 1;
        Qt.callLater(root.focusTerminal);
    }

    function closeCurrentTerminal() {
        if (terminalTabs.count <= 1)
            return;
        terminalTabs.remove(currentTerminalIndex, 1);
        currentTerminalIndex = Math.max(0, Math.min(currentTerminalIndex, terminalTabs.count - 1));
        Qt.callLater(root.focusTerminal);
    }

    function selectTerminal(index) {
        if (index < 0 || index >= terminalTabs.count)
            return;
        currentTerminalIndex = index;
        Qt.callLater(root.focusTerminal);
    }

    function nextTerminal() {
        if (terminalTabs.count < 2)
            return;
        currentTerminalIndex = (currentTerminalIndex + 1) % terminalTabs.count;
        Qt.callLater(root.focusTerminal);
    }

    function previousTerminal() {
        if (terminalTabs.count < 2)
            return;
        currentTerminalIndex = (currentTerminalIndex - 1 + terminalTabs.count) % terminalTabs.count;
        Qt.callLater(root.focusTerminal);
    }

    function handleSessionSignal(session, fallbackTitle) {
        if (!session)
            return;

        if (session.title === "__QS_NEXT__") {
            session.setTitle(fallbackTitle || "");
            root.nextTerminal();
        } else if (session.title === "__QS_PREV__") {
            session.setTitle(fallbackTitle || "");
            root.previousTerminal();
        }
    }

    function newTerminalFromCurrent() {
        const item = root.currentTerminalItem();
        const cwd = item && item.session ? item.session.currentDir : (Quickshell.env("HOME") || "/");
        root.addTerminal(cwd);
    }

    function openInKitty() {
        const item = root.currentTerminalItem();
        const cwd = item && item.session ? item.session.currentDir : (Quickshell.env("HOME") || "/");
        Quickshell.execDetached([
            "bash",
            "-lc",
            `cd '${StringUtils.shellSingleQuoteEscape(cwd)}' && exec ${Config.options.apps.terminal} fish`
        ]);
    }

    onActiveFocusChanged: {
        if (activeFocus)
            Qt.callLater(root.focusTerminal);
    }

    onVisibleChanged: {
        if (visible)
            Qt.callLater(root.focusTerminal);
    }

    Component.onCompleted: {
        if (terminalTabs.count === 0)
            root.addTerminal(Quickshell.env("HOME") || "/");
    }

    Action {
        shortcut: "Ctrl+Shift+T"
        onTriggered: root.newTerminalFromCurrent()
    }

    Action {
        shortcut: "Ctrl+Shift+W"
        onTriggered: root.closeCurrentTerminal()
    }

    Action {
        shortcut: "Ctrl+Tab"
        onTriggered: root.nextTerminal()
    }

    Action {
        shortcut: "Ctrl+Shift+Tab"
        onTriggered: root.previousTerminal()
    }

    Action {
        shortcut: "Alt+Right"
        onTriggered: root.nextTerminal()
    }

    Action {
        shortcut: "Alt+Left"
        onTriggered: root.previousTerminal()
    }

    Action {
        shortcut: "Ctrl+PageDown"
        onTriggered: root.nextTerminal()
    }

    Action {
        shortcut: "Ctrl+PageUp"
        onTriggered: root.previousTerminal()
    }

    ListModel {
        id: terminalTabs
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer1Hover

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    MaterialSymbol {
                        text: "terminal"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        text: Translation.tr("Fish Console")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.title
                        color: Appearance.colors.colOnLayer2
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Repeater {
                        model: [
                            {
                                icon: "add",
                                tooltip: Translation.tr("New terminal"),
                                action: () => root.newTerminalFromCurrent()
                            },
                            {
                                icon: "content_copy",
                                tooltip: Translation.tr("Copy terminal selection"),
                                action: () => {
                                    const item = root.currentTerminalItem();
                                    if (item && item.term) item.term.copyClipboard();
                                }
                            },
                            {
                                icon: "content_paste",
                                tooltip: Translation.tr("Paste clipboard"),
                                action: () => {
                                    const item = root.currentTerminalItem();
                                    if (item && item.term) item.term.pasteClipboard();
                                }
                            },
                            {
                                icon: "cleaning_services",
                                tooltip: Translation.tr("Clear terminal"),
                                action: () => {
                                    const item = root.currentTerminalItem();
                                    if (item && item.term) item.term.sendText("clear\n");
                                }
                            },
                            {
                                icon: "open_in_new",
                                tooltip: Translation.tr("Open in real kitty"),
                                action: () => root.openInKitty()
                            }
                        ]

                        delegate: RippleButton {
                            required property var modelData
                            property var buttonModel: modelData
                            implicitWidth: 30
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer3
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            onClicked: buttonModel.action()

                            contentItem: MaterialSymbol {
                                text: buttonModel.icon
                                iconSize: 18
                                color: Appearance.colors.colOnLayer3
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            StyledToolTip {
                                text: buttonModel.tooltip
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 42
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                ListView {
                    id: terminalTabList
                    anchors.fill: parent
                    anchors.margins: 6
                    orientation: ListView.Horizontal
                    spacing: 6
                    model: terminalTabs
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        required property int index
                        required property string label
                        color: index === root.currentTerminalIndex ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                        radius: 15
                        implicitWidth: tabRow.implicitWidth + 16
                        implicitHeight: 30

                        RowLayout {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 6

                            StyledText {
                                text: label
                                color: index === root.currentTerminalIndex ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            RippleButton {
                                visible: terminalTabs.count > 1
                                implicitWidth: 18
                                implicitHeight: 18
                                buttonRadius: 9
                                colBackground: "transparent"
                                colBackgroundHover: Qt.alpha(Appearance.colors.colOnLayer3, 0.08)
                                onClicked: {
                                    terminalTabs.remove(index, 1);
                                    root.currentTerminalIndex = Math.max(0, Math.min(root.currentTerminalIndex, terminalTabs.count - 1));
                                    Qt.callLater(root.focusTerminal);
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 14
                                    color: index === root.currentTerminalIndex ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                                }
                            }
                        }

                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: root.selectTerminal(index)
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Switch terminal: Alt+Left/Right or Ctrl+Tab")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                horizontalAlignment: Text.AlignRight
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colLayer2Hover
                clip: true

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: root.focusTerminal()
                }

                StackLayout {
                    anchors.fill: parent
                    currentIndex: root.currentTerminalIndex

                    Repeater {
                        id: terminalRepeater
                        model: terminalTabs

                        delegate: Item {
                            required property int index
                            required property string workingDirectory
                            required property string label
                            property bool terminalReady: false
                            property alias term: term
                            property alias session: termSession

                            Rectangle {
                                anchors.fill: parent
                                color: Appearance.colors.colLayer2
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: !terminalReady
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
                                        text: Translation.tr("Loading terminal...")
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                }
                            }

                            QMLTermWidget {
                                id: term
                                anchors.fill: parent
                                anchors.margins: 1
                                focus: index === root.currentTerminalIndex
                                activeFocusOnTab: true
                                font.family: "Noto Sans Mono"
                                font.pointSize: 11
                                colorScheme: "BreezeModified"
                                session: QMLTermSession {
                                    id: termSession
                                    initialWorkingDirectory: workingDirectory
                                    shellProgram: "fish"
                                    shellProgramArgs: [
                                        "-i",
                                        "-C",
                                        `source '${StringUtils.shellSingleQuoteEscape(Quickshell.shellPath("scripts/console/sidebar-shell.fish"))}'`
                                    ]
                                }

                                onImagePainted: parent.terminalReady = true
                                Connections {
                                    target: termSession

                                    function onTitleChanged() {
                                        root.handleSessionSignal(termSession, label);
                                    }
                                }

                                Component.onCompleted: {
                                    parent.terminalReady = false;
                                    termSession.setTitle(label);
                                    termSession.startShellProgram();
                                    if (index === root.currentTerminalIndex)
                                        Qt.callLater(root.focusTerminal);
                                }
                            }
                        }
                    }
                }

                Loader {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 4

                    readonly property var currentTerm: {
                        const item = root.currentTerminalItem();
                        return item ? item.term : null;
                    }

                    active: currentTerm !== null
                    sourceComponent: QMLTermScrollbar {
                        terminal: parent.currentTerm

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
}
