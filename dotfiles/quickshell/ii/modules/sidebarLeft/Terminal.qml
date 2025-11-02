import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io





Item {
    id: root
    property var inputField: tagInputField
    readonly property var responses: Booru.responses
    property string previewDownloadPath: Directories.booruPreviews
    property string downloadPath: Directories.booruDownloads
    property string nsfwPath: Directories.booruDownloadsNsfw
    property string commandPrefix: "/"

    property string shelltype: "zsh"


    property real scrollOnNewResponse: 100
    property int tagSuggestionDelay: 210
    property var suggestionQuery: ""
    property var suggestionList: []

    property color colStdout: "#ffffff"
    property color colStderr: "#ff6b6b"
    property color colCmd:    "#b0b0b0"



    property var consoleHistory: []   // [{ role: "cmd"|"stdout"|"stderr"|"sys", text: "..." }]
    property var shell: shellLoader.item



    


    function stripAnsi(s) {
        // regex abbastanza robusta per le SGR e simili
        return s.replace(/\x1B\[[0-9;?]*[ -/]*[@-~]/g, "")
    }

    function appendConsoleLine(s) {
        const line = (s ?? "").toString()
        if (!line.length) return
        consoleHistory = consoleHistory.concat([{ role: "stdout", text: stripAnsi(line) }])
    }

    function appendStderrLine(s) {
        const line = (s ?? "").toString()
        if (!line.length) return
        consoleHistory = consoleHistory.concat([{ role: "stderr", text: stripAnsi(line) }])
    }

    // 1) Build the command for the selected shell
    function buildShellCommand() {
        var env = ["/usr/bin/env", "TERM=dumb", "NO_COLOR=1"]
        if (shelltype === "bash")   return env.concat(["bash", "--noprofile", "--norc"])
        if (shelltype === "zsh")    return env.concat(["zsh", "-f"])        // no rc files
        if (shelltype === "fish")   return env.concat(["fish"])
        return env.concat([shelltype])                                      // fallback
    }

    // 2) Spawn a brand-new Process instance
    function spawnNewShell() {
        // try to terminate the old one
        if (shell && shell.running) { try { shell.signal(15) } catch(e) {} } // SIGTERM
        // recreate the Process by reloading the Loader
        shellLoader.sourceComponent = null
        shellLoader.sourceComponent = shellComponent
        consoleHistory = consoleHistory.concat([{ role: "sys", text: "[new shell: " + shelltype + "]" }])
    }


    Component {
        id: shellComponent
        Process {
            command: root.buildShellCommand()
            stdinEnabled: true
            running: true
            workingDirectory: Quickshell.env("HOME") || "/"
            stdout: SplitParser { splitMarker: "\n"; onRead: root.appendConsoleLine(data) }
            stderr: SplitParser { splitMarker: "\n"; onRead: root.appendStderrLine(data) }
            onStarted:  root.consoleHistory = root.consoleHistory.concat([{ role: "sys", text: "[shell started pid=" + processId + "]" }])
            onExited: function(code) { root.consoleHistory = root.consoleHistory.concat([{ role: "sys", text: "[exit " + code + "]" }]) }
        }
    }



    // Loader che ospita la shell corrente
    Loader {
        id: shellLoader
        sourceComponent: shellComponent
    }

    property var allCommands: [
        {
            name: "mode",
            description: Translation.tr("Set the current API provider"),
            execute: (args) => {
                Booru.setProvider(args[0]);
            }
        },
        {
            name: "clear",
            description: Translation.tr("Clear the current list of images"),
            execute: () => {
                Booru.clearResponses();
            }
        },
        {
            name: "next",
            description: Translation.tr("Get the next page of results"),
            execute: () => {
                if (root.responses.length > 0) {
                    const lastResponse = root.responses[root.responses.length - 1];
                    root.handleInput(`${lastResponse.tags.join(" ")} ${parseInt(lastResponse.page) + 1}`);
                }
            }
        },
        {
            name: "lewd",
            description: Translation.tr("Allow NSFW content"),
            execute: () => {
                Persistent.states.booru.allowNsfw = true;
            }
        },
        {
            name: "shell",
            description: Translation.tr("Change shell"),
            execute: (args) => {
                if (!args[0]) return
                shelltype = args[0]
                root.spawnNewShell()                // immediately restart with new shell
            }
        },
        {
            name: "newshell",
            description: Translation.tr("New shell"),
            execute: () => { root.spawnNewShell() } // /newshell
        },
    ]

    function handleInput(inputText) {
        if (inputText.startsWith(root.commandPrefix)) {
            // Handle special commands
            const command = inputText.split(" ")[0].substring(1);
            const args = inputText.split(" ").slice(1);
            const commandObj = root.allCommands.find(cmd => cmd.name === `${command}`);
            if (commandObj) {
                commandObj.execute(args);
            } else {
                Booru.addSystemMessage(Translation.tr("Unknown command: ") + command);
            }
        }
        else if (inputText.trim() == "+") {
            if (root.responses.length > 0) {
                const lastResponse = root.responses[root.responses.length - 1]
                root.handleInput(lastResponse.tags.join(" ") + ` ${parseInt(lastResponse.page) + 1}`);
            }
        }
        else {
            // Esegui il testo come comando in shell
            const cmd = inputText.trim()
            if (!cmd.length) return

            // echo del comando
            consoleHistory = consoleHistory.concat([{ role: "cmd", text: "$ " + cmd }])

            // invio al processo
            if (shell && shell.running) {
                shell.write(cmd + "\n")
            } else {
                consoleHistory = consoleHistory.concat([{ role: "sys", text: "[no shell running]" }])
            }
        }


    }

    onFocusChanged: (focus) => {
        if (focus) {
            tagInputField.forceActiveFocus()
        }
    }

    Keys.onPressed: (event) => {
        tagInputField.forceActiveFocus()
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                booruResponseListView.contentY = Math.max(0, booruResponseListView.contentY - booruResponseListView.height / 2)
                event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
                booruResponseListView.contentY = Math.min(booruResponseListView.contentHeight - booruResponseListView.height / 2, booruResponseListView.contentY + booruResponseListView.height / 2)
                event.accepted = true
            }
        }
    }


    ColumnLayout {
        id: columnLayout
        anchors.fill: parent

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            StyledListView { // Console output
                id: booruResponseListView
                anchors.fill: parent
                spacing: 8
                

                property int lastResponseLength: 0

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                Behavior on contentY {
                    NumberAnimation {
                        id: scrollAnim
                        duration: Appearance.animation.scroll.duration
                        easing.type: Appearance.animation.scroll.type
                        easing.bezierCurve: Appearance.animation.scroll.bezierCurve
                    }
                }

                model: ScriptModel {
                    values: {
                        if (root.consoleHistory.length > booruResponseListView.lastResponseLength) {
                            if (booruResponseListView.lastResponseLength > 0)
                                booruResponseListView.contentY = booruResponseListView.contentY + root.scrollOnNewResponse
                            booruResponseListView.lastResponseLength = root.consoleHistory.length
                        }
                        return root.consoleHistory
                    }
                }

                delegate: Item {
                    width: ListView.view.width
                    implicitHeight: lineText.implicitHeight

                    StyledText {
                        id: lineText
                        width: parent.width
                        wrapMode: Text.Wrap
                        font.family: "monospace"
                        text: modelData.text
                        color: modelData.role === "stderr" ? root.colStderr
                            : modelData.role === "cmd"    ? root.colCmd
                            : root.colStdout
                    }

                }
            }



            Item { // Placeholder when list is empty
                opacity: root.responses.length === 0 ? 1 : 0
                //visible: opacity > 0
                anchors.fill: parent
                enabled: false
                visible: root.consoleHistory.length === 0


                Behavior on opacity {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        iconSize: 50
                        color: Appearance.m3colors.m3inverseOnSurface
                        text: "terminal"
                    }
                    StyledText {
                        id: widgetNameText
                        Layout.alignment: Qt.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.family: Appearance.font.family.title
                        color: Appearance.m3colors.m3inverseOnSurface
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Terminal")
                    }
                }
            }
        }

        DescriptionBox { // Tag suggestion description
            text: root.suggestionList[tagSuggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1
        }

        FlowButtonGroup { // Tag suggestions
            id: tagSuggestions
            visible: root.suggestionList.length > 0 && tagInputField.text.length > 0
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                id: tagSuggestionRepeater
                model: {
                    tagSuggestions.selectedIndex = 0
                    return root.suggestionList.slice(0, 10)
                }
                delegate: ApiCommandButton {
                    id: tagButton
                    colBackground: tagSuggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false
                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 5
                        StyledText {
                            Layout.fillWidth: false
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSecondaryContainer
                            horizontalAlignment: Text.AlignRight
                            text: modelData.displayName ?? modelData.name
                        }
                        StyledText {
                            Layout.fillWidth: false
                            visible: modelData.count !== undefined
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSecondaryContainer
                            horizontalAlignment: Text.AlignLeft
                            text: modelData.count ?? ""
                        }
                    }

                    onHoveredChanged: {
                        if (tagButton.hovered) {
                            tagSuggestions.selectedIndex = index;
                        }
                    }
                    onClicked: {
                        tagSuggestions.acceptTag(modelData.name)
                    }
                }
            }

            function acceptTag(tag) {
                const words = tagInputField.text.trim().split(/\s+/);
                if (words.length > 0) {
                    words[words.length - 1] = tag;
                } else {
                    words.push(tag);
                }
                const updatedText = words.join(" ") + " ";
                tagInputField.text = updatedText;
                tagInputField.cursorPosition = tagInputField.text.length;
                tagInputField.forceActiveFocus();
            }

            function acceptSelectedTag() {
                if (tagSuggestions.selectedIndex >= 0 && tagSuggestions.selectedIndex < tagSuggestionRepeater.count) {
                    const tag = root.suggestionList[tagSuggestions.selectedIndex].name;
                    tagSuggestions.acceptTag(tag);
                }
            }
        }

        Rectangle { // Tag input area
            id: tagInputContainer
            property real columnSpacing: 5
            Layout.fillWidth: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            implicitWidth: tagInputField.implicitWidth
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin 
                + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + columnSpacing, 45)
            clip: true
            border.color: Appearance.colors.colOutlineVariant
            border.width: 1

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            RowLayout { // Input field and send button
                id: inputFieldRowLayout
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 5
                spacing: 0

                StyledTextArea { // The actual TextArea
                    id: tagInputField
                    wrapMode: TextArea.Wrap
                    Layout.fillWidth: true
                    padding: 10
                    color: activeFocus ? "#FFFFFFFF" : "#cacaca"
                    renderType: Text.NativeRendering
                    placeholderText: Translation.tr('Enter tags, or "%1" for commands').arg(root.commandPrefix)

                    background: null

                    property Timer searchTimer: Timer { // Timer for tag suggestions
                        interval: root.tagSuggestionDelay
                        repeat: false
                        onTriggered: {
                            const inputText = tagInputField.text
                            const words = inputText.trim().split(/\s+/);
                            if (words.length > 0) {
                                Booru.triggerTagSearch(words[words.length - 1]);
                            }
                        }
                    }

                    onTextChanged: { // Handle tag suggestions
                        if(tagInputField.text.length === 0) {
                            root.suggestionQuery = ""
                            root.suggestionList = []
                            searchTimer.stop();
                            return
                        }
                        if(tagInputField.text.startsWith(`${root.commandPrefix}mode`)) {
                            root.suggestionQuery = tagInputField.text.split(" ")[1] ?? ""
                            const providerResults = Fuzzy.go(root.suggestionQuery, Booru.providerList.map(provider => {
                                return {
                                    name: Fuzzy.prepare(provider),
                                    obj: provider,
                                }
                            }), {
                                all: true,
                                key: "name"
                            })
                            root.suggestionList = providerResults.map(provider => {
                                return {
                                    name: `${tagInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "mode ") : ""}${provider.target}`,
                                    displayName: `${Booru.providers[provider.target].name}`,
                                    description: `${Booru.providers[provider.target].description}`,
                                }
                            })
                            searchTimer.stop();
                            return
                        }
                        if(tagInputField.text.startsWith(root.commandPrefix)) {
                            root.suggestionQuery = tagInputField.text
                            root.suggestionList = root.allCommands.filter(cmd => cmd.name.startsWith(tagInputField.text.substring(1))).map(cmd => {
                                return {
                                    name: `${root.commandPrefix}${cmd.name}`,
                                    description: `${cmd.description}`,
                                }
                            })
                            searchTimer.stop();
                            return
                        }
                        searchTimer.restart();
                    }

                    function accept() {
                        root.handleInput(text)
                        text = ""
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Tab) {
                            tagSuggestions.acceptSelectedTag();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            tagSuggestions.selectedIndex = Math.max(0, tagSuggestions.selectedIndex - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down) {
                            tagSuggestions.selectedIndex = Math.min(root.suggestionList.length - 1, tagSuggestions.selectedIndex + 1);
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                // Insert newline
                                tagInputField.insert(tagInputField.cursorPosition, "\n")
                                event.accepted = true
                            } else { // Accept text
                                const inputText = tagInputField.text
                                root.handleInput(inputText)
                                tagInputField.clear()
                                event.accepted = true
                            }
                        }
                    }
                }

                RippleButton { // Send button
                    id: sendButton
                    Layout.alignment: Qt.AlignTop
                    Layout.rightMargin: 5
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    enabled: tagInputField.text.length > 0
                    toggled: enabled

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const inputText = tagInputField.text
                            root.handleInput(inputText)
                            tagInputField.clear()
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        // fill: sendButton.enabled ? 1 : 0
                        color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                        text: "send"
                    }
                }
            }

            RowLayout { // Controls
                id: commandButtonsRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                anchors.leftMargin: 5
                anchors.rightMargin: 5
                spacing: 5

                property var commandsShown: [
                    {
                        name: "shell",
                        sendDirectly: false,
                    },
                    {
                        name: "clear",
                        sendDirectly: true,
                    }, 
                ]

                property var commandsShown2: [
                    {
                        name: "newshell",
                        sendDirectly: true,
                    },
                ]

                ApiInputBoxIndicator { // Tool indicator
                    icon: "api"
                    text: shelltype
                    tooltipText: Translation.tr("Current Shell: " + shelltype + "\nSet it with %2mode PROVIDER")
                        .arg(Booru.providers[Booru.currentProvider].url)
                        .arg(root.commandPrefix)
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                    text: "•"
                }

                ButtonGroup {
                    padding: 0
                    Repeater { // Command buttons
                        id: commandRepeater2
                        model: commandButtonsRow.commandsShown2
                        delegate: ApiCommandButton {
                            property string commandRepresentation: `${root.commandPrefix}${modelData.name}`
                            buttonText: commandRepresentation
                            colBackground: Appearance.colors.colLayer2

                            onClicked: {
                                if(modelData.sendDirectly) {
                                    root.handleInput(commandRepresentation)
                                } else {
                                    tagInputField.text = commandRepresentation + " "
                                    tagInputField.cursorPosition = tagInputField.text.length
                                    tagInputField.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                ButtonGroup {
                    padding: 0
                    Repeater { // Command buttons
                        id: commandRepeater
                        model: commandButtonsRow.commandsShown
                        delegate: ApiCommandButton {
                            property string commandRepresentation: `${root.commandPrefix}${modelData.name}`
                            buttonText: commandRepresentation
                            colBackground: Appearance.colors.colLayer2

                            onClicked: {
                                if(modelData.sendDirectly) {
                                    root.handleInput(commandRepresentation)
                                } else {
                                    tagInputField.text = commandRepresentation + " "
                                    tagInputField.cursorPosition = tagInputField.text.length
                                    tagInputField.forceActiveFocus()
                                }
                                if (modelData.name === "clear") {
                                    tagInputField.text = ""
                                }
                            }
                        }
                    }
                }
            }

        }
    }
}
