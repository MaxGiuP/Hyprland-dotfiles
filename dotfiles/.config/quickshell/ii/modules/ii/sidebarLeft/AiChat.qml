import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.aiChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Item {
    id: root
    property real padding: 4
    property var inputField: messageInputField
    property string commandPrefix: "/"

    property var suggestionQuery: ""
    property var suggestionList: []
    property var supportedCliAgents: ["codex", "claude", "gemini"]
    property bool showOllamaManagerDialog: false
    property string ollamaDialogMode: "suggested"

    onFocusChanged: focus => {
        if (focus) {
            root.inputField.forceActiveFocus();
        }
    }

    Keys.onPressed: event => {
        messageInputField.forceActiveFocus();
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2);
                event.accepted = true;
            }
        }
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            Ai.clearMessages();
        }
    }

    property var allCommands: [
        {
            name: "model",
            description: Translation.tr("Choose model"),
            execute: args => {
                if (args.length === 0 || (args[0] ?? "").trim().length === 0) {
                    const entries = Ai.accessibleModelSuggestionList.map(modelId => {
                        const m = Ai.models[modelId];
                        if (!m) return `- ${modelId}`;
                        const where = m.endpoint && m.endpoint.includes("localhost") ? "local" : "online";
                        const marker = modelId === Ai.currentModelId ? " (current)" : "";
                        return `- ${modelId}: ${m.name} [${where}]${marker}`;
                    }).join("\n");
                    Ai.addMessage(
                        Translation.tr("## Available models\n\n%1\n\nUse `%2model MODEL_ID` to switch.")
                            .arg(entries.length > 0 ? entries : Translation.tr("No models found"))
                            .arg(root.commandPrefix),
                        Ai.interfaceRole
                    );
                    return;
                }
                Ai.setModel(args[0]);
            }
        },
        {
            name: "ollama",
            description: Translation.tr("Refresh Ollama status/models."),
            execute: () => {
                Ai.refreshOllamaStatus();
                Ai.addMessage(
                    Translation.tr("Refreshing Ollama status...\n\n- Installed models: %1\n- Runtime: %2")
                        .arg(Ai.localOllamaModels.length)
                        .arg(Ai.ollamaRunning ? Translation.tr("running") : Translation.tr("offline")),
                    Ai.interfaceRole
                );
            }
        },
        {
            name: "tool",
            description: Translation.tr("Set the tool to use for the model."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.addMessage(Translation.tr("Usage: %1tool TOOL_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                } else {
                    const tool = args[0];
                    const switched = Ai.setTool(tool);
                    if (switched) {
                        Ai.addMessage(Translation.tr("Tool set to: %1").arg(tool), Ai.interfaceRole);
                    }
                }
            }
        },
        {
            name: "agent",
            description: Translation.tr("Run CLI agent: /agent codex|claude|gemini PROMPT"),
            execute: args => {
                if (args.length < 2) {
                    Ai.addMessage(Translation.tr("Usage: %1agent codex|claude|gemini YOUR_PROMPT").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                const agent = (args.shift() || "").toLowerCase().trim();
                const prompt = args.join(" ").trim();
                runCliAgent(agent, prompt);
            }
        },
        {
            name: "attach",
            description: Translation.tr("Attach a file. Only works with Gemini."),
            execute: args => {
                Ai.attachFile(args.join(" ").trim());
            }
        },
        {
            name: "prompt",
            description: Translation.tr("Set the system prompt for the model."),
            execute: args => {
                if (args.length === 0 || args[0] === "get") {
                    Ai.printPrompt();
                    return;
                }
                Ai.loadPrompt(args.join(" ").trim());
            }
        },
        {
            name: "key",
            description: Translation.tr("Set API key"),
            execute: args => {
                if (args[0] == "get") {
                    Ai.printApiKey();
                } else {
                    Ai.setApiKey(args[0]);
                }
            }
        },
        {
            name: "save",
            description: Translation.tr("Save chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1save CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.saveChat(joinedArgs);
            }
        },
        {
            name: "load",
            description: Translation.tr("Load chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1load CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.loadChat(joinedArgs);
            }
        },
        {
            name: "clear",
            description: Translation.tr("Clear chat history"),
            execute: () => {
                Ai.clearMessages();
            }
        },
        {
            name: "temp",
            description: Translation.tr("Set temperature (randomness) of the model. Values range between 0 to 2 for Gemini, 0 to 1 for other models. Default is 0.5."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.printTemperature();
                } else {
                    const temp = parseFloat(args[0]);
                    Ai.setTemperature(temp);
                }
            }
        },
        {
            name: "test",
            description: Translation.tr("Markdown test"),
            execute: () => {
                Ai.addMessage(`
<think>
A longer think block to test revealing animation
OwO wem ipsum dowo sit amet, consekituwet awipiscing ewit, sed do eiuwsmod tempow inwididunt ut wabowe et dowo mawa. Ut enim ad minim weniam, quis nostwud exeucitation uwuwamcow bowowis nisi ut awiquip ex ea commowo consequat. Duuis aute iwuwe dowo in wepwependewit in wowuptate velit esse ciwwum dowo eu fugiat nuwa pawiatuw. Excepteuw sint occaecat cupidatat non pwowoident, sunt in cuwpa qui officia desewunt mowit anim id est wabowum. Meouw! >w<
Mowe uwu wem ipsum!
</think>
## ✏️ Markdown test
### Formatting

- *Italic*, \`Monospace\`, **Bold**, [Link](https://example.com)
- Arch lincox icon <img src="${Quickshell.shellPath("assets/icons/arch-symbolic.svg")}" height="${Appearance.font.pixelSize.small}"/>

### Table

Quickshell vs AGS/Astal

|                          | Quickshell       | AGS/Astal         |
|--------------------------|------------------|-------------------|
| UI Toolkit               | Qt               | Gtk3/Gtk4         |
| Language                 | QML              | Js/Ts/Lua         |
| Reactivity               | Implied          | Needs declaration |
| Widget placement         | Mildly difficult | More intuitive    |
| Bluetooth & Wifi support | ❌               | ✅                |
| No-delay keybinds        | ✅               | ❌                |
| Development              | New APIs         | New syntax        |

### Code block

Just a hello world...

\`\`\`cpp
#include <bits/stdc++.h>
// This is intentionally very long to test scrolling
const std::string GREETING = \"UwU\";
int main(int argc, char* argv[]) {
    std::cout << GREETING;
}
\`\`\`

### LaTeX


Inline w/ dollar signs: $\\frac{1}{2} = \\frac{2}{4}$

Inline w/ double dollar signs: $$\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$

Inline w/ backslash and square brackets \\[\\int_0^\\infty \\frac{1}{x^2} dx = \\infty\\]

Inline w/ backslash and round brackets \\(e^{i\\pi} + 1 = 0\\)
`, Ai.interfaceRole);
            }
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
                Ai.addMessage(Translation.tr("Unknown command: ") + command, Ai.interfaceRole);
            }
        } else {
            Ai.sendUserMessage(inputText);
        }

        // Always scroll to bottom when user sends a message
        messageListView.positionViewAtEnd();
    }

    function openOllamaManagerDialog(mode) {
        root.ollamaDialogMode = mode;
        root.showOllamaManagerDialog = true;
        Qt.callLater(() => ollamaManagerDialog.forceActiveFocus());
    }

    Process {
        id: decodeImageAndAttachProc
        property string imageDecodePath: Directories.cliphistDecode
        property string imageDecodeFileName: "image"
        property string imageDecodeFilePath: `${imageDecodePath}/${imageDecodeFileName}`
        function handleEntry(entry: string) {
            imageDecodeFileName = parseInt(entry.match(/^(\d+)\t/)[1]);
            decodeImageAndAttachProc.exec(["bash", "-c", `[ -f ${imageDecodeFilePath} ] || echo '${StringUtils.shellSingleQuoteEscape(entry)}' | ${Cliphist.cliphistBinary} decode > '${imageDecodeFilePath}'`]);
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Ai.attachFile(imageDecodeFilePath);
            } else {
                console.error("[AiChat] Failed to decode image in clipboard content");
            }
        }
    }

    Process {
        id: cliAgentProc
        property string activeAgent: ""
        property string prompt: ""
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                cliAgentProc.buffer += data + "\n";
            }
        }
        stderr: SplitParser {
            onRead: data => {
                cliAgentProc.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            const output = cliAgentProc.buffer.trim();
            if (exitCode === 0) {
                Ai.addMessage(
                    `### ${cliAgentProc.activeAgent} CLI\n\n${output.length > 0 ? output : Translation.tr("No output")}`,
                    Ai.interfaceRole
                );
            } else {
                Ai.addMessage(
                    Translation.tr("%1 CLI failed (exit %2)\n\n%3").arg(cliAgentProc.activeAgent).arg(exitCode).arg(output),
                    Ai.interfaceRole
                );
            }
            cliAgentProc.buffer = "";
        }
    }

    Process {
        id: ollamaServeProc
        command: ["ollama", "serve"]
        onRunningChanged: {
            if (!running) {
                Qt.callLater(() => Ai.refreshOllamaStatus());
            }
        }
    }

    Process {
        id: ollamaKillProc
        command: ["pkill", "ollama"]
        onExited: {
            Qt.callLater(() => Ai.refreshOllamaStatus());
        }
    }

    function runCliAgent(agent, prompt) {
        if (root.supportedCliAgents.indexOf(agent) === -1) {
            Ai.addMessage(Translation.tr("Unsupported agent. Use one of: %1").arg(root.supportedCliAgents.join(", ")), Ai.interfaceRole);
            return;
        }
        const escapedPrompt = StringUtils.shellSingleQuoteEscape(prompt);
        let script = "";
        if (agent === "codex") {
            script = `command -v codex >/dev/null || { echo 'codex not found'; exit 127; }; codex exec '${escapedPrompt}'`;
        } else if (agent === "claude") {
            script = `command -v claude >/dev/null || { echo 'claude not found'; exit 127; }; claude -p '${escapedPrompt}'`;
        } else {
            script = `command -v gemini >/dev/null || { echo 'gemini not found'; exit 127; }; gemini -p '${escapedPrompt}'`;
        }
        cliAgentProc.activeAgent = agent;
        cliAgentProc.prompt = prompt;
        cliAgentProc.buffer = "";
        cliAgentProc.command = ["bash", "-lc", script];
        cliAgentProc.running = true;
        Ai.addMessage(Translation.tr("Running %1 CLI...").arg(agent), Ai.interfaceRole);
    }

    component StatusItem: MouseArea {
        id: statusItem
        property string icon
        property string iconSource: ""
        property string statusText
        property string description
        hoverEnabled: true
        implicitHeight: statusItemRowLayout.implicitHeight
        implicitWidth: statusItemRowLayout.implicitWidth

        RowLayout {
            id: statusItemRowLayout
            spacing: 0
            CustomIcon {
                visible: statusItem.iconSource.length > 0
                width: Appearance.font.pixelSize.huge
                height: Appearance.font.pixelSize.huge
                source: statusItem.iconSource
                colorize: true
                color: Appearance.colors.colSubtext
            }
            MaterialSymbol {
                visible: statusItem.iconSource.length === 0
                text: statusItem.icon
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colSubtext
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                text: statusItem.statusText
                color: Appearance.colors.colSubtext
                animateChange: true
            }
        }

        StyledToolTip {
            text: statusItem.description
            extraVisibleCondition: false
            alternativeVisibleCondition: statusItem.containsMouse
        }
    }

    component StatusSeparator: Rectangle {
        implicitWidth: 4
        implicitHeight: 4
        radius: implicitWidth / 2
        color: Appearance.colors.colOutlineVariant
    }

    ColumnLayout {
        id: columnLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        Item {
            // Messages
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: swipeView.width
                    height: swipeView.height
                    radius: Appearance.rounding.small
                }
            }

            StyledRectangularShadow {
                z: 1
                target: statusBg
                opacity: messageListView.atYBeginning ? 0 : 1
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
            Rectangle {
                id: statusBg
                z: 2
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: 4
                }
                implicitWidth: statusRowLayout.implicitWidth + 10 * 2
                implicitHeight: Math.max(statusRowLayout.implicitHeight, 38)
                radius: Appearance.rounding.normal - root.padding
                color: messageListView.atYBeginning ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Base
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                RowLayout {
                    id: statusRowLayout
                    anchors.centerIn: parent
                    spacing: 10

                    StatusItem {
                        iconSource: "ollama-symbolic.svg"
                        statusText: Ai.ollamaRunning ? Translation.tr("Ollama up") : Translation.tr("Ollama down")
                        description: Translation.tr("Local Ollama runtime status\\nAuto-refreshed every few seconds")
                    }
                    StatusSeparator {}
                    StatusItem {
                        icon: Ai.currentModelHasApiKey ? "key" : "key_off"
                        statusText: ""
                        description: Ai.currentModelHasApiKey ? Translation.tr("API key is set\nChange with /key YOUR_API_KEY") : Translation.tr("No API key\nSet it with /key YOUR_API_KEY")
                    }
                    StatusSeparator {}
                    StatusItem {
                        icon: "device_thermostat"
                        statusText: Ai.temperature.toFixed(1)
                        description: Translation.tr("Temperature\nChange with /temp VALUE")
                    }
                    StatusSeparator {
                        visible: Ai.tokenCount.total > 0
                    }
                    StatusItem {
                        visible: Ai.tokenCount.total > 0
                        icon: "token"
                        statusText: Ai.tokenCount.total
                        description: Translation.tr("Total token count\nInput: %1\nOutput: %2").arg(Ai.tokenCount.input).arg(Ai.tokenCount.output)
                    }
                }
            }

            Rectangle {
                id: modelUpdatesCard
                z: 2
                visible: Ai.ollamaMutationBusy || Ai.discoveredOllamaRecommendations.length > 0 || Ai.localOllamaModels.length > 0 || Ai.recentGeminiArrivals.length > 0
                anchors {
                    top: statusBg.bottom
                    topMargin: 8
                    left: parent.left
                    right: parent.right
                    leftMargin: 8
                    rightMargin: 8
                }
                implicitHeight: modelUpdatesLayout.implicitHeight + 18
                radius: Appearance.rounding.normal - root.padding
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                ColumnLayout {
                    id: modelUpdatesLayout
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "system_update_alt"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Ollama models")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                            color: Appearance.colors.colOnLayer1
                        }

                        DialogButton {
                            buttonText: Translation.tr("Refresh")
                            downAction: () => {
                                Ai.refreshOnlineModels();
                                Ai.refreshOllamaStatus();
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("%1 installed | %2 suggested | %3 successors")
                            .arg(Ai.localOllamaModels.length)
                            .arg(Ai.storeOllamaRecommendations.length)
                            .arg(Ai.successorStoreOllamaRecommendations.length)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        visible: Ai.ollamaMutationBusy
                        implicitHeight: installStatusLayout.implicitHeight + 16
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer3
                        border.width: 1
                        border.color: Appearance.colors.colOutlineVariant

                        ColumnLayout {
                            id: installStatusLayout
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            StyledText {
                                Layout.fillWidth: true
                                color: Appearance.colors.colOnLayer1
                                font.bold: true
                                text: Ai.ollamaInstallingModelId.length > 0
                                    ? (Ai.ollamaInstallPaused
                                        ? Translation.tr("Paused %1").arg(Ai.ollamaInstallingModelId)
                                        : Translation.tr("Installing %1").arg(Ai.ollamaInstallingModelId))
                                    : Translation.tr("Removing %1").arg(Ai.ollamaRemovingModelId)
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                text: Ai.ollamaInstallingModelId.length > 0
                                    ? Ai.ollamaInstallStatusText
                                    : Ai.ollamaRemoveStatusText
                            }

                            StyledProgressBar {
                                Layout.fillWidth: true
                                visible: Ai.ollamaInstallingModelId.length > 0 && Ai.ollamaInstallProgress >= 0
                                value: Ai.ollamaInstallProgress
                            }

                            StyledIndeterminateProgressBar {
                                Layout.fillWidth: true
                                visible: (Ai.ollamaInstallingModelId.length > 0 && Ai.ollamaInstallProgress < 0)
                                    || Ai.ollamaRemovingModelId.length > 0
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: Ai.ollamaInstallingModelId.length > 0
                                spacing: 8

                                Item {
                                    Layout.fillWidth: true
                                }

                                DialogButton {
                                    enabled: !Ai.ollamaInstallCancelRequested
                                    buttonText: Ai.ollamaInstallPaused
                                        ? Translation.tr("Resume")
                                        : Translation.tr("Pause")
                                    downAction: () => {
                                        if (Ai.ollamaInstallPaused)
                                            Ai.resumeOllamaInstall();
                                        else
                                            Ai.pauseOllamaInstall();
                                    }
                                }

                                DialogButton {
                                    enabled: !Ai.ollamaInstallCancelRequested
                                    buttonText: Translation.tr("Cancel")
                                    colEnabled: Appearance.colors.colError
                                    downAction: () => Ai.cancelOllamaInstall()
                                }
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        DialogButton {
                            buttonText: Translation.tr("Installed")
                            downAction: () => root.openOllamaManagerDialog("installed")
                        }

                        DialogButton {
                            buttonText: Translation.tr("Suggested")
                            downAction: () => root.openOllamaManagerDialog("suggested")
                        }

                        DialogButton {
                            buttonText: Translation.tr("Successors")
                            downAction: () => root.openOllamaManagerDialog("successors")
                        }
                    }
                }
            }

            ScrollEdgeFade {
                z: 1
                target: messageListView
                vertical: true
            }

            StyledListView { // Message list
                id: messageListView
                z: 0
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    top: modelUpdatesCard.visible ? modelUpdatesCard.bottom : statusBg.bottom
                    topMargin: 8
                }
                spacing: 10
                popin: false

                touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                property int lastResponseLength: 0
                onContentHeightChanged: {
                    if (atYEnd)
                        Qt.callLater(positionViewAtEnd);
                }
                onCountChanged: {
                    // Auto-scroll when new messages are added
                    if (atYEnd)
                        Qt.callLater(positionViewAtEnd);
                }

                add: null // Prevent function calls from being janky

                model: ScriptModel {
                    values: Ai.messageIDs.filter(id => {
                        const message = Ai.messageByID[id];
                        return message?.visibleToUser ?? true;
                    })
                }
                delegate: AiMessage {
                    required property var modelData
                    required property int index
                    messageIndex: index
                    messageData: {
                        Ai.messageByID[modelData];
                    }
                    messageInputField: root.inputField
                }
            }

            PagePlaceholder {
                z: 1
                shown: Ai.messageIDs.length === 0
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    top: modelUpdatesCard.visible ? modelUpdatesCard.bottom : statusBg.bottom
                    topMargin: 8
                }
                icon: "neurology"
                title: Translation.tr("Large language models")
                description: Translation.tr("Type /key to get started with online models\nCtrl+O to expand sidebar\nCtrl+P to pin sidebar\nCtrl+D to detach sidebar")
                shape: MaterialShape.Shape.Circle
            }

            ScrollToBottomButton {
                z: 3
                target: messageListView
            }
        }

        DescriptionBox {
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1
        }

        FlowButtonGroup { // Suggestions
            id: suggestions
            visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                id: suggestionRepeater
                model: {
                    suggestions.selectedIndex = 0;
                    return root.suggestionList.slice(0, 10);
                }
                delegate: ApiCommandButton {
                    id: commandButton
                    colBackground: suggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false
                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.displayName ?? modelData.name
                    }

                    onHoveredChanged: {
                        if (commandButton.hovered) {
                            suggestions.selectedIndex = index;
                        }
                    }
                    onClicked: {
                        suggestions.acceptSuggestion(modelData.name);
                    }
                }
            }

            function acceptSuggestion(word) {
                const words = messageInputField.text.trim().split(/\s+/);
                if (words.length > 0) {
                    words[words.length - 1] = word;
                } else {
                    words.push(word);
                }
                const updatedText = words.join(" ") + " ";
                messageInputField.text = updatedText;
                messageInputField.cursorPosition = messageInputField.text.length;
                messageInputField.forceActiveFocus();
            }

            function acceptSelectedWord() {
                if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < suggestionRepeater.count) {
                    const word = root.suggestionList[suggestions.selectedIndex].name;
                    suggestions.acceptSuggestion(word);
                }
            }
        }

        Rectangle { // Input area
            id: inputWrapper
            property real spacing: 5
            z: 10
            Layout.fillWidth: true
            radius: Appearance.rounding.normal - root.padding
            color: Appearance.colors.colLayer2
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + spacing, 45) + (attachedFileIndicator.implicitHeight + spacing + attachedFileIndicator.anchors.topMargin)
            clip: true
            layer.enabled: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            AttachedFileIndicator {
                id: attachedFileIndicator
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: visible ? 5 : 0
                }
                filePath: Ai.pendingFilePath
                onRemove: Ai.attachFile("")
            }

            RowLayout { // Input field and send button
                id: inputFieldRowLayout
                anchors {
                    top: attachedFileIndicator.bottom
                    left: parent.left
                    right: parent.right
                    topMargin: 5
                }
                spacing: 0

                StyledTextArea { // The actual TextArea
                    id: messageInputField
                    wrapMode: TextArea.Wrap
                    Layout.fillWidth: true
                    padding: 10
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    placeholderText: Translation.tr('Message the model... "%1" for commands').arg(root.commandPrefix)

                    background: null

                    onTextChanged: {
                        // Handle suggestions
                        if (messageInputField.text.length === 0) {
                            root.suggestionQuery = "";
                            root.suggestionList = [];
                            return;
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}model`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                            const suggestedModels = Ai.accessibleModelSuggestionList;
                            if (root.suggestionQuery.trim().length === 0) {
                                root.suggestionList = suggestedModels.map(modelId => {
                                    return {
                                        name: `${root.commandPrefix}model ${modelId}`,
                                        displayName: `${Ai.models[modelId].name}`,
                                        description: `${Ai.models[modelId].description}`
                                    };
                                });
                            } else {
                                const modelResults = Fuzzy.go(root.suggestionQuery, suggestedModels.map(model => {
                                    return {
                                        name: Fuzzy.prepare(model),
                                        obj: model
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = modelResults.map(model => {
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "model ") : ""}${model.target}`,
                                        displayName: `${Ai.models[model.target].name}`,
                                        description: `${Ai.models[model.target].description}`
                                    };
                                });
                            }
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}prompt`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                            const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.promptFiles.map(file => {
                                return {
                                    name: Fuzzy.prepare(file),
                                    obj: file
                                };
                            }), {
                                all: true,
                                key: "name"
                            });
                            root.suggestionList = promptFileResults.map(file => {
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "prompt ") : ""}${file.target}`,
                                    displayName: `${FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target))}`,
                                    description: Translation.tr("Load prompt from %1").arg(file.target)
                                };
                            });
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}save`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                            const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                return {
                                    name: Fuzzy.prepare(file),
                                    obj: file
                                };
                            }), {
                                all: true,
                                key: "name"
                            });
                            root.suggestionList = promptFileResults.map(file => {
                                const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "save ") : ""}${chatName}`,
                                    displayName: `${chatName}`,
                                    description: Translation.tr("Save chat to %1").arg(chatName)
                                };
                            });
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}load`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                            const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                return {
                                    name: Fuzzy.prepare(file),
                                    obj: file
                                };
                            }), {
                                all: true,
                                key: "name"
                            });
                            root.suggestionList = promptFileResults.map(file => {
                                const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "load ") : ""}${chatName}`,
                                    displayName: `${chatName}`,
                                    description: Translation.tr(`Load chat from %1`).arg(file.target)
                                };
                            });
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}tool`)) {
                            root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                            const toolResults = Fuzzy.go(root.suggestionQuery, Ai.availableTools.map(tool => {
                                return {
                                    name: Fuzzy.prepare(tool),
                                    obj: tool
                                };
                            }), {
                                all: true,
                                key: "name"
                            });
                            root.suggestionList = toolResults.map(tool => {
                                const toolName = tool.target;
                                return {
                                    name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "tool ") : ""}${tool.target}`,
                                    displayName: toolName,
                                    description: Ai.toolDescriptions[toolName]
                                };
                            });
                        } else if (messageInputField.text.startsWith(`${root.commandPrefix}agent`)) {
                            const args = messageInputField.text.split(" ").slice(1);
                            const agentQuery = args[0] ?? "";
                            root.suggestionList = root.supportedCliAgents
                                .filter(name => name.startsWith(agentQuery))
                                .map(name => {
                                    return {
                                        name: `${root.commandPrefix}agent ${name} `,
                                        displayName: name,
                                        description: Translation.tr("Run prompt using %1 CLI").arg(name)
                                    };
                                });
                        } else if (messageInputField.text.startsWith(root.commandPrefix)) {
                            root.suggestionQuery = messageInputField.text;
                            root.suggestionList = root.allCommands.filter(cmd => cmd.name.startsWith(messageInputField.text.substring(1))).map(cmd => {
                                return {
                                    name: `${root.commandPrefix}${cmd.name}`,
                                    description: `${cmd.description}`
                                };
                            });
                        }
                    }

                    function accept() {
                        root.handleInput(text);
                        text = "";
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            suggestions.acceptSelectedWord();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up && suggestions.visible) {
                            suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down && suggestions.visible) {
                            suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                // Insert newline
                                messageInputField.insert(messageInputField.cursorPosition, "\n");
                                event.accepted = true;
                            } else {
                                // Accept text
                                const inputText = messageInputField.text;
                                messageInputField.clear();
                                root.handleInput(inputText);
                                event.accepted = true;
                            }
                        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                            // Intercept Ctrl+V to handle image/file pasting
                            if (event.modifiers & Qt.ShiftModifier) {
                                // Let Shift+Ctrl+V = plain paste
                                messageInputField.text += Quickshell.clipboardText;
                                event.accepted = true;
                                return;
                            }
                            // Try image paste first
                            const currentClipboardEntry = Cliphist.entries[0];
                            const cleanCliphistEntry = StringUtils.cleanCliphistEntry(currentClipboardEntry);
                            if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(currentClipboardEntry)) {
                                // First entry = currently copied entry = image?
                                decodeImageAndAttachProc.handleEntry(currentClipboardEntry);
                                event.accepted = true;
                                return;
                            } else if (cleanCliphistEntry.startsWith("file://")) {
                                // First entry = currently copied entry = image?
                                const fileName = decodeURIComponent(cleanCliphistEntry);
                                Ai.attachFile(fileName);
                                event.accepted = true;
                                return;
                            }
                            event.accepted = false; // No image, let text pasting proceed
                        } else if (event.key === Qt.Key_Escape) {
                            // Esc to detach file
                            if (Ai.pendingFilePath.length > 0) {
                                Ai.attachFile("");
                                event.accepted = true;
                            } else {
                                event.accepted = false;
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
                    enabled: messageInputField.text.length > 0
                    toggled: enabled

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const inputText = messageInputField.text;
                            root.handleInput(inputText);
                            messageInputField.clear();
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                        text: "arrow_upward"
                    }
                }
            }

            RowLayout { // Controls
                id: commandButtonsRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                anchors.leftMargin: 10
                anchors.rightMargin: 5
                spacing: 4

                property var commandsShown: [
                    {
                        name: "",
                        sendDirectly: false,
                        dontAddSpace: true
                    },
                    {
                        name: "clear",
                        sendDirectly: true
                    },
                ]

                ApiInputBoxIndicator {
                    // Model indicator
                    icon: "api"
                    text: Ai.getModel().name
                    tooltipText: Translation.tr("Current model: %1\nSet it with %2model MODEL").arg(Ai.getModel().name).arg(root.commandPrefix)
                }

                Item {
                    Layout.fillWidth: true
                }

                ApiCommandButton {
                    buttonText: Ai.ollamaRunning ? Translation.tr("■ Ollama") : Translation.tr("▶ Ollama")
                    toggled: Ai.ollamaRunning
                    downAction: () => {
                        if (!Ai.ollamaRunning) {
                            ollamaServeProc.running = true;
                        } else {
                            ollamaServeProc.running = false;
                            ollamaKillProc.running = true;
                        }
                    }
                }

                ButtonGroup {
                    // Command buttons
                    padding: 0

                    Repeater {
                        // Command buttons
                        model: commandButtonsRow.commandsShown
                        delegate: ApiCommandButton {
                            property string commandRepresentation: `${root.commandPrefix}${modelData.name}`
                            buttonText: commandRepresentation
                            downAction: () => {
                                if (modelData.sendDirectly) {
                                    root.handleInput(commandRepresentation);
                                } else {
                                    messageInputField.text = commandRepresentation + (modelData.dontAddSpace ? "" : " ");
                                    messageInputField.cursorPosition = messageInputField.text.length;
                                    messageInputField.forceActiveFocus();
                                }
                                if (modelData.name === "clear") {
                                    messageInputField.text = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: ollamaManagerDialog
        property string customModelId: ""
        readonly property string dialogMode: root.ollamaDialogMode
        readonly property var shownRecommendations: dialogMode === "successors" ? Ai.successorStoreOllamaRecommendations : Ai.storeOllamaRecommendations
        property string selectedUseCaseFilter: "all"
        readonly property var useCaseFilters: [
            {"id": "all", "label": Translation.tr("All")},
            {"id": "chat", "label": Translation.tr("Chat")},
            {"id": "coding", "label": Translation.tr("Coding")},
            {"id": "reasoning", "label": Translation.tr("Reasoning")},
            {"id": "agents", "label": Translation.tr("Agents")},
            {"id": "lightweight", "label": Translation.tr("Lightweight")},
        ]

        signal dismiss()
        onDismiss: root.showOllamaManagerDialog = false
        onVisibleChanged: {
            if (visible)
                selectedUseCaseFilter = "all";
        }

        anchors.fill: parent
        z: 100
        visible: root.showOllamaManagerDialog
        color: Appearance.colors.colScrim
        focus: visible

        function recommendationUseCases(entry) {
            return entry?.use_cases ?? [];
        }

        function matchesUseCase(entry) {
            if (selectedUseCaseFilter === "all")
                return true;
            return recommendationUseCases(entry).indexOf(selectedUseCaseFilter) !== -1;
        }

        function filteredRecommendations() {
            return shownRecommendations.filter(entry => matchesUseCase(entry));
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                ollamaManagerDialog.dismiss();
                event.accepted = true;
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: ollamaManagerDialog.dismiss()
        }

        Rectangle {
            id: ollamaDialogSurface
            anchors.centerIn: parent
            width: Math.min(ollamaManagerDialog.width - 20, 760)
            height: Math.min(ollamaDialogContent.implicitHeight + 32, ollamaManagerDialog.height - 20, 700)
            radius: Appearance.rounding.large
            color: Appearance.m3colors.m3surfaceContainerHigh

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            ColumnLayout {
                id: ollamaDialogContent
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                StyledText {
                    Layout.fillWidth: true
                    text: ollamaManagerDialog.dialogMode === "installed"
                        ? Translation.tr("Installed Ollama models")
                        : (ollamaManagerDialog.dialogMode === "successors"
                            ? Translation.tr("Potential Ollama successors")
                            : Translation.tr("Latest suggested Ollama models"))
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                    font.bold: true
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    text: ollamaManagerDialog.dialogMode === "installed"
                        ? Translation.tr("These are the Ollama models currently available on this machine. Remove the ones you no longer want.")
                        : (ollamaManagerDialog.dialogMode === "successors"
                            ? Translation.tr("These suggestions are newer models that fit families you already have installed.")
                            : Translation.tr("These are the latest suggested Ollama models for your setup. Install them from here."))
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: ollamaManagerDialog.dialogMode !== "installed"
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Browse curated local models by use case, compare storage size, then install directly from here.")
                }

                Flow {
                    Layout.fillWidth: true
                    visible: ollamaManagerDialog.dialogMode !== "installed"
                    spacing: 8

                    Repeater {
                        model: ollamaManagerDialog.useCaseFilters
                        delegate: DialogButton {
                            required property var modelData
                            buttonText: modelData.label
                            toggled: ollamaManagerDialog.selectedUseCaseFilter === modelData.id
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colBackgroundToggled: Appearance.colors.colPrimary
                            colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                            colText: toggled ? colForegroundToggled : Appearance.colors.colOnLayer1
                            downAction: () => ollamaManagerDialog.selectedUseCaseFilter = modelData.id
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: false

                    MaterialTextField {
                        id: customInstallField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Custom model id, e.g. qwen3:4b")
                        text: ollamaManagerDialog.customModelId
                        onTextChanged: ollamaManagerDialog.customModelId = text
                        onAccepted: {
                            const modelId = text.trim();
                            if (modelId.length === 0) return;
                            Ai.queueOllamaInstall([modelId]);
                            text = "";
                            ollamaManagerDialog.customModelId = "";
                        }
                    }

                    DialogButton {
                        buttonText: Translation.tr("Install")
                        downAction: () => {
                            const modelId = customInstallField.text.trim();
                            if (modelId.length === 0) return;
                            Ai.queueOllamaInstall([modelId]);
                            customInstallField.text = "";
                            ollamaManagerDialog.customModelId = "";
                        }
                    }

                    DialogButton {
                        buttonText: Translation.tr("Refresh")
                        downAction: () => {
                            Ai.refreshOnlineModels();
                            Ai.refreshOllamaStatus();
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: Ai.ollamaInstallingModelId.length > 0 || Ai.ollamaRemovingModelId.length > 0
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnSecondaryContainer
                    text: Ai.ollamaInstallingModelId.length > 0 ? Ai.ollamaInstallStatusText : Ai.ollamaRemoveStatusText
                }

                StyledProgressBar {
                    Layout.fillWidth: true
                    visible: Ai.ollamaInstallingModelId.length > 0 && Ai.ollamaInstallProgress >= 0
                    value: Ai.ollamaInstallProgress
                }

                StyledIndeterminateProgressBar {
                    Layout.fillWidth: true
                    visible: (Ai.ollamaInstallingModelId.length > 0 && Ai.ollamaInstallProgress < 0) || Ai.ollamaRemovingModelId.length > 0
                }

                ScrollView {
                    id: ollamaManagerScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Column {
                        width: ollamaManagerScroll.availableWidth
                        spacing: 14

                        Column {
                            width: parent.width
                            spacing: 8
                            visible: ollamaManagerDialog.dialogMode !== "installed"

                            StyledText {
                                width: parent.width
                                text: ollamaManagerDialog.dialogMode === "successors"
                                    ? Translation.tr("Potential successors")
                                    : Translation.tr("Recommended models")
                                color: Appearance.colors.colOnLayer1
                                font.bold: true
                            }

                            StyledText {
                                width: parent.width
                                visible: ollamaManagerDialog.filteredRecommendations().length === 0
                                wrapMode: Text.WordWrap
                                color: Appearance.colors.colSubtext
                                text: ollamaManagerDialog.dialogMode === "successors"
                                    ? Translation.tr("No successor suggestions match this filter right now.")
                                    : Translation.tr("No suggested models match this filter right now.")
                            }

                            Repeater {
                                model: ollamaManagerDialog.filteredRecommendations()
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property string installId: modelData.install_id ?? ""
                                    readonly property string installState: Ai.ollamaInstallStateFor(installId)
                                    readonly property string successorContext: Ai.successorContextForRecommendation(modelData)
                                    readonly property string storageSize: modelData.storage_size?.length > 0
                                        ? modelData.storage_size
                                        : ""
                                    readonly property var useCases: modelData.use_cases ?? []
                                    readonly property string hardwareHint: modelData.hardware_hint ?? ""
                                    width: parent.width
                                    implicitHeight: recommendedCardLayout.implicitHeight + 16
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer3
                                    border.width: 1
                                    border.color: Appearance.colors.colOutlineVariant

                                    ColumnLayout {
                                        id: recommendedCardLayout
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 8

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: modelData.display_name ?? installId
                                                    color: Appearance.colors.colOnLayer1
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    color: Appearance.colors.colSubtext
                                                    text: installId
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            DialogButton {
                                                enabled: !Ai.ollamaRemoveBusy && installState === "available"
                                                buttonText: installState === "installed"
                                                    ? Translation.tr("Installed")
                                                    : (installState === "paused"
                                                    ? Translation.tr("Paused")
                                                    : (installState === "installing"
                                                    ? Translation.tr("Installing")
                                                    : (installState === "queued" ? Translation.tr("Queued") : Translation.tr("Install"))))
                                                colBackground: installState === "installed"
                                                    ? Appearance.colors.colLayer2
                                                    : Appearance.colors.colLayer3
                                                colBackgroundHover: installState === "installed"
                                                    ? Appearance.colors.colLayer2
                                                    : Appearance.colors.colLayer3Hover
                                                colText: installState === "installed"
                                                    ? Appearance.colors.colSubtext
                                                    : Appearance.colors.colPrimary
                                                downAction: () => Ai.queueOllamaInstall([installId])
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            color: Appearance.colors.colOnLayer1
                                            text: modelData.reason?.length > 0 ? modelData.reason : (modelData.description ?? "")
                                        }

                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Repeater {
                                                model: [
                                                    ...(storageSize.length > 0 ? [Translation.tr("Storage: %1").arg(storageSize)] : []),
                                                    ...(hardwareHint.length > 0 ? [hardwareHint] : []),
                                                    ...useCases.map(tag => {
                                                        if (tag === "chat") return Translation.tr("Chat");
                                                        if (tag === "coding") return Translation.tr("Coding");
                                                        if (tag === "reasoning") return Translation.tr("Reasoning");
                                                        if (tag === "agents") return Translation.tr("Agents");
                                                        if (tag === "lightweight") return Translation.tr("Lightweight");
                                                        return tag;
                                                    }),
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    implicitHeight: chipLabel.implicitHeight + 8
                                                    implicitWidth: chipLabel.implicitWidth + 12
                                                    radius: Appearance.rounding.full
                                                    color: Appearance.colors.colLayer2

                                                    StyledText {
                                                        id: chipLabel
                                                        anchors.centerIn: parent
                                                        text: parent.modelData
                                                        color: Appearance.colors.colSubtext
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                    }
                                                }
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: successorContext.length > 0
                                            color: Appearance.colors.colPrimary
                                            wrapMode: Text.WordWrap
                                            text: Translation.tr("Successor to your %1").arg(successorContext)
                                        }

                                        StyledText {
                                                Layout.fillWidth: true
                                            visible: modelData.updated_label?.length > 0
                                            color: Appearance.colors.colSubtext
                                            text: Translation.tr("Updated %1").arg(modelData.updated_label ?? "")
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                visible: ollamaManagerDialog.dialogMode !== "installed"
                                implicitHeight: manualInstallLayout.implicitHeight + 16
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colLayer2
                                border.width: 1
                                border.color: Appearance.colors.colOutlineVariant

                                ColumnLayout {
                                    id: manualInstallLayout
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Manual install")
                                        color: Appearance.colors.colOnLayer1
                                        font.bold: true
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        color: Appearance.colors.colSubtext
                                        text: Translation.tr("Know the exact Ollama model id already? Install it manually here.")
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        MaterialTextField {
                                            Layout.fillWidth: true
                                            placeholderText: Translation.tr("Custom model id, e.g. qwen3:4b")
                                            text: ollamaManagerDialog.customModelId
                                            onTextChanged: ollamaManagerDialog.customModelId = text
                                            onAccepted: {
                                                const modelId = text.trim();
                                                if (modelId.length === 0) return;
                                                Ai.queueOllamaInstall([modelId]);
                                                text = "";
                                                ollamaManagerDialog.customModelId = "";
                                            }
                                        }

                                        DialogButton {
                                            buttonText: Translation.tr("Install")
                                            downAction: () => {
                                                const modelId = ollamaManagerDialog.customModelId.trim();
                                                if (modelId.length === 0) return;
                                                Ai.queueOllamaInstall([modelId]);
                                                ollamaManagerDialog.customModelId = "";
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 8
                            visible: ollamaManagerDialog.dialogMode === "installed"

                            StyledText {
                                width: parent.width
                                text: Translation.tr("Installed")
                                color: Appearance.colors.colOnLayer1
                                font.bold: true
                            }

                            StyledText {
                                width: parent.width
                                visible: Ai.localOllamaModels.length === 0
                                wrapMode: Text.WordWrap
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("No local Ollama models are installed yet.")
                            }

                            Repeater {
                                model: Ai.localOllamaModels
                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property string removeState: Ai.ollamaRemoveStateFor(modelData)
                                    width: parent.width
                                    implicitHeight: installedRow.implicitHeight + 12
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colLayer3

                                    RowLayout {
                                        id: installedRow
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 8

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: Ai.guessModelName(modelData)
                                                color: Appearance.colors.colOnLayer1
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                color: Appearance.colors.colSubtext
                                                text: modelData
                                                elide: Text.ElideRight
                                            }
                                        }

                                        ApiCommandButton {
                                            enabled: !Ai.ollamaInstallBusy && removeState === "installed"
                                            buttonText: removeState === "removing"
                                                ? Translation.tr("Removing")
                                                : (removeState === "queued" ? Translation.tr("Queued") : Translation.tr("Remove"))
                                            downAction: () => Ai.queueOllamaRemoval([modelData])
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight

                    DialogButton {
                        buttonText: Translation.tr("Close")
                        downAction: () => ollamaManagerDialog.dismiss()
                    }
                }
            }
        }
    }
}
