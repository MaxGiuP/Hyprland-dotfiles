import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760

    property var englishTranslations: ({})
    property var targetTranslations: ({})
    property string rawTargetJson: "{}"
    onRawTargetJsonChanged: {
        if (!rawJsonEditor.activeFocus)
            rawJsonEditor.text = rawTargetJson
    }

    function selectedLocaleCode() {
        const raw = localeInput.text.trim()
        if (!raw.length || raw === "auto")
            return Qt.locale().name
        return raw
    }

    function targetTranslationPath() {
        return `${Translation.translationsDir}/${selectedLocaleCode()}.json`
    }

    function parseJson(text, fallback) {
        try {
            return JSON.parse(text)
        } catch (error) {
            return fallback
        }
    }

    function prettyJson(value) {
        return JSON.stringify(value, null, 2)
    }

    readonly property var filteredTranslationKeys: {
        const term = translationSearchField.text.trim().toLowerCase()
        return Object.keys(englishTranslations).sort((a, b) => a.localeCompare(b)).filter(key => {
            const translated = `${targetTranslations[key] || ""}`.toLowerCase()
            if (!term.length) return true
            return key.toLowerCase().includes(term) || translated.includes(term)
        })
    }

    Process {
        id: translationProc
        property string locale: ""
        command: [Directories.aiTranslationScriptPath, translationProc.locale]
    }

    FileView {
        id: englishTranslationFile
        path: `${Translation.translationsDir}/en_US.json`
        watchChanges: true
        onLoaded: root.englishTranslations = root.parseJson(text(), {})
        onLoadFailed: root.englishTranslations = ({})
        onFileChanged: reload()
    }

    FileView {
        id: targetTranslationFile
        path: root.targetTranslationPath()
        watchChanges: true
        onLoaded: {
            root.rawTargetJson = text() || "{}"
            root.targetTranslations = root.parseJson(root.rawTargetJson, {})
        }
        onLoadFailed: {
            root.rawTargetJson = "{}"
            root.targetTranslations = ({})
        }
        onFileChanged: reload()
    }

    ContentSection {
        icon: "language"
        title: Translation.tr("Date, time & language")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Keep language, clock formatting, and translation generation in one place instead of splitting them across general shell settings.")
        }
    }

    ContentSection {
        icon: "translate"
        title: Translation.tr("Language")

        StyledComboBox {
            Layout.fillWidth: true
            buttonIcon: "language"
            textRole: "displayName"
            model: [
                {
                    displayName: Translation.tr("Auto (System)"),
                    value: "auto"
                },
                ...Translation.allAvailableLanguages.map(lang => ({
                    displayName: lang,
                    value: lang
                }))
            ]
            currentIndex: {
                const index = model.findIndex(item => item.value === Config.options.language.ui)
                return index !== -1 ? index : 0
            }
            onActivated: index => Config.options.language.ui = model[index].value
        }

        ConfigRow {
            MaterialTextArea {
                id: localeInput
                Layout.fillWidth: true
                placeholderText: Translation.tr("Locale code, e.g. fr_FR, de_DE, zh_CN...")
                text: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
                onTextChanged: {
                    targetTranslationFile.path = root.targetTranslationPath()
                    targetTranslationFile.reload()
                }
            }

            RippleButtonWithIcon {
                id: generateTranslationBtn
                Layout.fillHeight: true
                nerdIcon: ""
                enabled: !translationProc.running || (translationProc.locale !== localeInput.text.trim())
                mainText: enabled ? Translation.tr("Generate translation") : Translation.tr("Generating…")
                onClicked: {
                    translationProc.locale = localeInput.text.trim()
                    translationProc.running = false
                    translationProc.running = true
                }
            }
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "refresh"
                mainText: Translation.tr("Reload locale file")
                onClicked: {
                    targetTranslationFile.path = root.targetTranslationPath()
                    targetTranslationFile.reload()
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "edit_document"
                mainText: Translation.tr("Open locale JSON file")
                onClicked: Qt.openUrlExternally(`file://${root.targetTranslationPath()}`)
            }
        }
    }

    ContentSection {
        icon: "dictionary"
        title: Translation.tr("Translation map")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("This shows the base English source string on the left and the current target locale translation on the right for %1.").arg(root.selectedLocaleCode())
        }

        MaterialTextField {
            id: translationSearchField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Filter English or translated text")
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 420
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            ListView {
                id: translationList
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                spacing: 8
                model: root.filteredTranslationKeys

                delegate: Rectangle {
                    required property string modelData
                    width: translationList.width
                    implicitHeight: row.implicitHeight + 12
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    RowLayout {
                        id: row
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            StyledText {
                                text: Translation.tr("English")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData
                                color: Appearance.colors.colOnLayer1
                                wrapMode: Text.Wrap
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            StyledText {
                                text: root.selectedLocaleCode()
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.targetTranslations[modelData] || ""
                                color: Appearance.colors.colOnLayer1
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "code"
        title: Translation.tr("Locale JSON editor")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Edit the raw translation JSON directly for %1. This writes to the locale file in the shell translations directory.").arg(root.selectedLocaleCode())
        }

        ScrollView {
            Layout.fillWidth: true
            implicitHeight: 360
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AsNeeded
            ScrollBar.vertical.policy: ScrollBar.AlwaysOn

            MaterialTextArea {
                id: rawJsonEditor
                width: parent.availableWidth
                wrapMode: TextEdit.NoWrap
                readOnly: false
                selectByMouse: true
                persistentSelection: true
                font.family: Appearance.font.family.monospace
                text: root.rawTargetJson
            }
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "save"
                mainText: Translation.tr("Save locale JSON")
                onClicked: {
                    const parsed = root.parseJson(rawJsonEditor.text, null)
                    if (parsed === null) return
                    const formatted = root.prettyJson(parsed)
                    targetTranslationFile.setText(formatted)
                    root.rawTargetJson = formatted
                    root.targetTranslations = parsed
                    targetTranslationFile.reload()
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "restore"
                mainText: Translation.tr("Reset editor from file")
                onClicked: {
                    targetTranslationFile.reload()
                }
            }
        }
    }

    ContentSection {
        icon: "schedule"
        title: Translation.tr("Time")

        ConfigSwitch {
            buttonIcon: "pace"
            text: Translation.tr("Second precision")
            checked: Config.options.time.secondPrecision
            onCheckedChanged: Config.options.time.secondPrecision = checked
        }

        ContentSubsection {
            title: Translation.tr("Clock format")

            ConfigSelectionArray {
                currentValue: Config.options.time.format
                onSelected: newValue => {
                    if (newValue === "hh:mm")
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME12\\b/TIME/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`])
                    else
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME\\b/TIME12/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`])

                    Config.options.time.format = newValue
                }
                options: [
                    { displayName: Translation.tr("24h"), value: "hh:mm" },
                    { displayName: Translation.tr("12h am/pm"), value: "h:mm ap" },
                    { displayName: Translation.tr("12h AM/PM"), value: "h:mm AP" }
                ]
            }
        }
    }
}
