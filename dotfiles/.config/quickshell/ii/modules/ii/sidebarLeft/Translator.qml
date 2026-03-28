import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.translator
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Translator widget with the `trans` commandline tool.
 */
Item {
    id: root

    // Sizes
    property real padding: 4

    // Widgets
    property var inputField: inputCanvas.inputTextArea

    // Widget variables
    property bool translationFor: false // Indicates if the translation is for an autocorrected text
    property string translatedText: ""
    property string primaryTranslation: ""
    property list<string> languages: []

    // Options
    property string targetLanguage: Config.options.language.translator.targetLanguage
    property string sourceLanguage: Config.options.language.translator.sourceLanguage
    property string hostLanguage: targetLanguage
    property var recentSourceLanguages: []
    property var recentTargetLanguages: []

    // States
    property bool showLanguageSelector: false
    property bool languageSelectorTarget: false // true for target language, false for source language

    function showLanguageSelectorDialog(isTargetLang: bool) {
        root.languageSelectorTarget = isTargetLang;
        root.showLanguageSelector = true
    }

    function rememberLanguage(lang, isTarget) {
        if (!lang || lang.length === 0) return;
        const list = isTarget ? root.recentTargetLanguages.slice(0) : root.recentSourceLanguages.slice(0);
        const filtered = list.filter(item => item !== lang);
        filtered.unshift(lang);
        const capped = filtered.slice(0, 4);
        if (isTarget) root.recentTargetLanguages = capped;
        else root.recentSourceLanguages = capped;
    }

    function applyQuickLanguage(lang, isTarget) {
        if (!lang || lang.length === 0) return;
        if (isTarget) {
            root.targetLanguage = lang;
            Config.options.language.translator.targetLanguage = lang;
            root.rememberLanguage(lang, true);
        } else {
            root.sourceLanguage = lang;
            Config.options.language.translator.sourceLanguage = lang;
            root.rememberLanguage(lang, false);
        }
        translateTimer.restart();
    }

    function swapLanguages() {
        const oldSource = root.sourceLanguage;
        const oldTarget = root.targetLanguage;
        const oldInput = root.inputField?.text ?? "";
        const oldPrimary = root.primaryTranslation ?? "";

        root.sourceLanguage = oldTarget;
        root.targetLanguage = oldSource;
        Config.options.language.translator.sourceLanguage = root.sourceLanguage;
        Config.options.language.translator.targetLanguage = root.targetLanguage;
        root.rememberLanguage(root.sourceLanguage, false);
        root.rememberLanguage(root.targetLanguage, true);

        // Swap only the direct translation phrase (not the full rich output block).
        if (oldPrimary.trim().length > 0) {
            root.inputField.text = oldPrimary.trim();
        } else {
            root.inputField.text = oldInput;
        }
        root.translatedText = "";
        root.primaryTranslation = "";

        translateTimer.restart();
    }

    function normalizeTranslationText(rawText) {
        if (!rawText) return "";
        // Strip ANSI color codes and normalize spacing for the UI text area.
        let text = rawText.replace(/\x1B\[[0-9;]*[A-Za-z]/g, "");
        text = text.replace(/\r/g, "");
        text = text.replace(/[ \t]+\n/g, "\n");
        text = text.replace(/\n{3,}/g, "\n\n");
        return text.trim();
    }

    function extractPrimaryTranslation(formattedText) {
        if (!formattedText || formattedText.trim().length === 0) return "";
        const lines = formattedText
            .split("\n")
            .map(line => line.trim())
            .filter(line => line.length > 0);
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (/^\[.*\]$/.test(line)) continue;
            if (/^dictionary\b/i.test(line)) continue;
            if (/^alternatives?\b/i.test(line)) continue;
            if (/^synonyms?\b/i.test(line)) continue;
            return line;
        }
        return lines.length > 0 ? lines[0] : "";
    }

    onFocusChanged: (focus) => {
        if (focus) {
            root.inputField.forceActiveFocus()
        }
    }

    Timer {
        id: translateTimer
        interval: Config.options.sidebar.translator.delay
        repeat: false
        onTriggered: () => {
            if (root.inputField.text.trim().length > 0) {
                // console.log("Translating with command:", translateProc.command);
                translateProc.running = false;
                translateProc.buffer = ""; // Clear the buffer
                translateProc.running = true; // Restart the process
            } else {
                root.translatedText = "";
            }
        }
    }

    Process {
        id: translateProc
        command: ["bash", "-c", `last=""; for eng in auto bing google yandex; do `
            + `out=$(trans -e "$eng" -no-ansi`
            + ` -no-init`
            + ` -no-warn`
            + ` -hl en`
            + ` -show-prompt-message n`
            + ` -show-languages n`
            + ` -show-original n`
            + ` -show-translation y`
            + ` -show-original-dictionary n`
            + ` -show-dictionary y`
            + ` -show-alternatives y`
            + ` -indent 2`
            + ` -width 120`
            + ` -source '${StringUtils.shellSingleQuoteEscape(root.sourceLanguage)}'`
            + ` -target '${StringUtils.shellSingleQuoteEscape(root.targetLanguage)}'`
            + ` '${StringUtils.shellSingleQuoteEscape(root.inputField.text.trim())}' 2>&1); `
            + `code=$?; if [ "$code" -eq 0 ] && [ -n "$out" ]; then printf "%s\\n" "$out"; exit 0; fi; `
            + `last="$out"; done; printf "%s\\n" "$last"; exit 1`]
        property string buffer: ""
        property string errBuffer: ""
        stdout: SplitParser {
            onRead: data => {
                translateProc.buffer += data + "\n";
            }
        }
        stderr: SplitParser {
            onRead: data => {
                translateProc.errBuffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            const preferred = translateProc.buffer.trim().length > 0 ? translateProc.buffer : translateProc.errBuffer;
            const formatted = root.normalizeTranslationText(preferred);
            if (formatted.length > 0) {
                root.translatedText = formatted;
                root.primaryTranslation = root.extractPrimaryTranslation(formatted);
            } else {
                root.translatedText = Translation.tr("No translation output.");
                root.primaryTranslation = "";
            }
            translateProc.buffer = "";
            translateProc.errBuffer = "";
        }
    }

    Process {
        id: getLanguagesProc
        command: ["trans", "-list-languages", "-no-bidi"]
        property list<string> bufferList: ["auto"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                getLanguagesProc.bufferList.push(data.trim());
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Ensure "auto" is always the first language
            let langs = getLanguagesProc.bufferList
                .filter(lang => lang.trim().length > 0 && lang !== "auto")
                .sort((a, b) => a.localeCompare(b));
            langs.unshift("auto");
            root.languages = langs;
            getLanguagesProc.bufferList = []; // Clear the buffer
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: contentColumn.implicitHeight

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    LanguageSelectorButton { // Target language button
                        id: targetLanguageButton
                        Layout.fillWidth: true
                        displayText: root.targetLanguage
                        onClicked: {
                            root.showLanguageSelectorDialog(true);
                        }
                    }

                    RippleButton {
                        implicitWidth: 30
                        implicitHeight: 24
                        buttonRadius: Appearance.rounding.verysmall
                        onClicked: root.swapLanguages()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "swap_horiz"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledToolTip {
                            text: Translation.tr("Swap input/output languages")
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.recentTargetLanguages.length > 1
                    spacing: 4
                    Repeater {
                        model: root.recentTargetLanguages.filter(lang => lang !== root.targetLanguage)
                        delegate: RippleButton {
                            implicitHeight: 20
                            implicitWidth: chipText.implicitWidth + 10
                            horizontalPadding: 5
                            buttonRadius: Appearance.rounding.verysmall
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            contentItem: StyledText {
                                id: chipText
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                            onClicked: root.applyQuickLanguage(modelData, true)
                        }
                    }
                }

                TextCanvas { // Content translation
                    id: outputCanvas
                    isInput: false
                    placeholderText: Translation.tr("Translation goes here...")
                    property bool hasTranslation: (root.translatedText.trim().length > 0)
                    text: hasTranslation ? root.translatedText : ""
                    GroupButton {
                        id: copyButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "content_copy"
                            color: copyButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }
                        onClicked: {
                            Quickshell.clipboardText = outputCanvas.displayedText
                        }
                    }
                    GroupButton {
                        id: searchButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "travel_explore"
                            color: searchButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }
                        onClicked: {
                            let url = Config.options.search.engineBaseUrl + outputCanvas.displayedText;
                            for (let site of Config.options.search.excludedSites) {
                                url += ` -site:${site}`;
                            }
                            Qt.openUrlExternally(url);
                        }
                    }
                }

            }    
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            LanguageSelectorButton { // Source language button
                id: sourceLanguageButton
                Layout.fillWidth: true
                displayText: root.sourceLanguage
                onClicked: {
                    root.showLanguageSelectorDialog(false);
                }
            }

            RippleButton {
                implicitWidth: 30
                implicitHeight: 24
                buttonRadius: Appearance.rounding.verysmall
                onClicked: root.swapLanguages()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "swap_horiz"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }
                StyledToolTip {
                    text: Translation.tr("Swap input/output languages")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.recentSourceLanguages.length > 1
            spacing: 4
            Repeater {
                model: root.recentSourceLanguages.filter(lang => lang !== root.sourceLanguage)
                delegate: RippleButton {
                    implicitHeight: 20
                    implicitWidth: chipText2.implicitWidth + 10
                    horizontalPadding: 5
                    buttonRadius: Appearance.rounding.verysmall
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    contentItem: StyledText {
                        id: chipText2
                        anchors.centerIn: parent
                        text: modelData
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                    }
                    onClicked: root.applyQuickLanguage(modelData, false)
                }
            }
        }

        TextCanvas { // Content input
            id: inputCanvas
            z: 3
            isInput: true
            placeholderText: Translation.tr("Enter text to translate...")
            onInputTextChanged: {
                translateTimer.restart();
            }
            GroupButton {
                id: pasteButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: "content_paste"
                    color: deleteButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                onClicked: {
                    root.inputField.text = Quickshell.clipboardText
                }
            }
            GroupButton {
                id: deleteButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                enabled: inputCanvas.inputTextArea.text.length > 0
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: "close"
                    color: deleteButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                onClicked: {
                    root.inputField.text = ""
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.showLanguageSelector
        visible: root.showLanguageSelector
        z: 9999
        sourceComponent: SelectionDialog {
            id: languageSelectorDialog
            titleText: Translation.tr("Select Language")
            items: root.languages
            defaultChoice: root.languageSelectorTarget ? root.targetLanguage : root.sourceLanguage
            onCanceled: () => {
                root.showLanguageSelector = false;
            }
            onSelected: (result) => {
                root.showLanguageSelector = false;
                if (!result || result.length === 0) return; // No selection made

                if (root.languageSelectorTarget) {
                    root.targetLanguage = result;
                    Config.options.language.translator.targetLanguage = result; // Save to config
                    root.rememberLanguage(result, true);
                } else {
                    root.sourceLanguage = result;
                    Config.options.language.translator.sourceLanguage = result; // Save to config
                    root.rememberLanguage(result, false);
                }

                translateTimer.restart(); // Restart translation after language change
            }
        }
    }

    Component.onCompleted: {
        root.rememberLanguage(root.sourceLanguage, false);
        root.rememberLanguage(root.targetLanguage, true);
    }
}
