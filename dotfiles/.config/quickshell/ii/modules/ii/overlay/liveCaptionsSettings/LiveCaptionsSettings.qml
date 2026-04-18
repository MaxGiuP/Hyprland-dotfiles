pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    title: Translation.tr("Live Captions")
    showCenterButton: true

    readonly property var speechQuickLanguages: [
        { id: "auto", label: Translation.tr("Auto") },
        { id: "en", label: Translation.tr("English") },
        { id: "it", label: Translation.tr("Italian") },
        { id: "de", label: Translation.tr("German") },
        { id: "fr", label: Translation.tr("French") }
    ]
    readonly property var speechMoreLanguages: [
        { id: "es", label: Translation.tr("Spanish") },
        { id: "pt", label: Translation.tr("Portuguese") },
        { id: "nl", label: Translation.tr("Dutch") },
        { id: "ru", label: Translation.tr("Russian") },
        { id: "zh", label: Translation.tr("Chinese") },
        { id: "ja", label: Translation.tr("Japanese") },
        { id: "ko", label: Translation.tr("Korean") },
        { id: "pl", label: Translation.tr("Polish") },
        { id: "ar", label: Translation.tr("Arabic") },
        { id: "hi", label: Translation.tr("Hindi") },
        { id: "tr", label: Translation.tr("Turkish") },
        { id: "sv", label: Translation.tr("Swedish") },
        { id: "da", label: Translation.tr("Danish") },
        { id: "fi", label: Translation.tr("Finnish") },
        { id: "cs", label: Translation.tr("Czech") },
        { id: "ro", label: Translation.tr("Romanian") }
    ]
    readonly property var targetQuickLanguages: [
        { id: "en", label: Translation.tr("English") },
        { id: "it", label: Translation.tr("Italian") },
        { id: "de", label: Translation.tr("German") },
        { id: "fr", label: Translation.tr("French") },
        { id: "es", label: Translation.tr("Spanish") }
    ]
    readonly property var targetMoreLanguages: [
        { id: "pt", label: Translation.tr("Portuguese") },
        { id: "nl", label: Translation.tr("Dutch") },
        { id: "ru", label: Translation.tr("Russian") },
        { id: "zh", label: Translation.tr("Chinese") },
        { id: "ja", label: Translation.tr("Japanese") },
        { id: "ko", label: Translation.tr("Korean") },
        { id: "pl", label: Translation.tr("Polish") },
        { id: "ar", label: Translation.tr("Arabic") },
        { id: "hi", label: Translation.tr("Hindi") },
        { id: "tr", label: Translation.tr("Turkish") },
        { id: "sv", label: Translation.tr("Swedish") },
        { id: "da", label: Translation.tr("Danish") },
        { id: "fi", label: Translation.tr("Finnish") },
        { id: "cs", label: Translation.tr("Czech") },
        { id: "ro", label: Translation.tr("Romanian") }
    ]

    readonly property bool captionOverlayOpen: (Persistent.states.overlay.open ?? []).includes("liveCaptions")
    readonly property bool translationOverlayOpen: (Persistent.states.overlay.open ?? []).includes("liveCaptionsTranslation")

    function toggleCaptionOverlay() {
        const open = Persistent.states.overlay.open ?? []
        if (root.captionOverlayOpen) {
            Persistent.states.overlay.open = open.filter(id => id !== "liveCaptions")
        } else {
            Persistent.states.overlay.open = [...open, "liveCaptions"]
            Persistent.states.overlay.liveCaptions.pinned = true
        }
    }

    function toggleTranslationOverlay() {
        const open = Persistent.states.overlay.open ?? []
        if (root.translationOverlayOpen) {
            Persistent.states.overlay.open = open.filter(id => id !== "liveCaptionsTranslation")
            LiveCaptions.setDisplayMode("captions")
        } else {
            Persistent.states.overlay.open = [...open, "liveCaptionsTranslation"]
            Persistent.states.overlay.liveCaptionsTranslation.pinned = true
            LiveCaptions.setDisplayMode("bilingual")
        }
    }

    contentItem: Rectangle {
        implicitWidth: 480
        implicitHeight: 400
        radius: root.contentRadius
        color: Appearance.colors.colLayer0
        clip: true

        Flickable {
            id: flickable
            anchors.fill: parent
            contentWidth: width
            contentHeight: settingsColumn.implicitHeight + 22
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: settingsColumn
                width: flickable.width - 22
                x: 11
                y: 11
                spacing: 10

                // Header row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: "subtitles"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        StyledText {
                            text: Translation.tr("Live captions")
                            font.bold: true
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            text: LiveCaptions.summaryText
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }

                    DialogButton {
                        buttonText: LiveCaptions.active ? Translation.tr("Stop") : Translation.tr("Start")
                        downAction: () => LiveCaptions.toggleRunning()
                    }
                }

                // Backend not installed
                Rectangle {
                    Layout.fillWidth: true
                    visible: !LiveCaptions.backendAvailable
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: backendLayout.implicitHeight + 14

                    ColumnLayout {
                        id: backendLayout
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 6

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colOnLayer1
                            text: LiveCaptions.backendStatusText
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            DialogButton {
                                buttonText: Translation.tr("Install backend")
                                downAction: () => LiveCaptions.openInstaller()
                            }

                            DialogButton {
                                buttonText: Translation.tr("Recheck")
                                downAction: () => LiveCaptions.refreshBackendAvailability()
                            }
                        }
                    }
                }

                // Status / error message
                Rectangle {
                    Layout.fillWidth: true
                    visible: LiveCaptions.statusMessage.trim().length > 0
                    radius: Appearance.rounding.small
                    color: LiveCaptions.status === "error"
                        ? Appearance.colors.colLayer2
                        : Appearance.colors.colLayer1
                    border.width: 1
                    border.color: LiveCaptions.status === "error"
                        ? Appearance.colors.colError
                        : Appearance.colors.colOutlineVariant
                    implicitHeight: statusText.implicitHeight + 14

                    StyledText {
                        id: statusText
                        anchors.fill: parent
                        anchors.margins: 7
                        wrapMode: Text.WordWrap
                        color: LiveCaptions.status === "error"
                            ? Appearance.colors.colError
                            : Appearance.colors.colSubtext
                        text: LiveCaptions.statusMessage
                    }
                }

                // Overlay section
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Overlay")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    DialogButton {
                        buttonText: Translation.tr("Captions box")
                        colBackground: root.captionOverlayOpen
                            ? Appearance.colors.colPrimaryContainer
                            : Appearance.colors.colLayer1
                        colBackgroundHover: root.captionOverlayOpen
                            ? Appearance.colors.colPrimaryContainer
                            : Appearance.colors.colLayer1Hover
                        colText: root.captionOverlayOpen
                            ? Appearance.colors.colOnLayer1
                            : Appearance.colors.colSubtext
                        downAction: () => root.toggleCaptionOverlay()
                    }

                    DialogButton {
                        buttonText: Translation.tr("Translation box")
                        colBackground: root.translationOverlayOpen
                            ? Appearance.colors.colPrimaryContainer
                            : Appearance.colors.colLayer1
                        colBackgroundHover: root.translationOverlayOpen
                            ? Appearance.colors.colPrimaryContainer
                            : Appearance.colors.colLayer1Hover
                        colText: root.translationOverlayOpen
                            ? Appearance.colors.colOnLayer1
                            : Appearance.colors.colSubtext
                        downAction: () => root.toggleTranslationOverlay()
                    }
                }

                // Source section
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Source")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { id: "system", label: Translation.tr("System audio") },
                            { id: "mic",    label: Translation.tr("Microphone") }
                        ]
                        delegate: DialogButton {
                            required property var modelData
                            buttonText: modelData.label
                            colBackground: LiveCaptions.sourceMode === modelData.id
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colLayer1
                            colBackgroundHover: LiveCaptions.sourceMode === modelData.id
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colLayer1Hover
                            colText: LiveCaptions.sourceMode === modelData.id
                                ? Appearance.colors.colOnLayer1
                                : Appearance.colors.colSubtext
                            downAction: () => LiveCaptions.setSourceMode(modelData.id)
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Backend")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: LiveCaptions.backendOptions
                        delegate: DialogButton {
                            required property var modelData
                            buttonText: modelData.label
                            colBackground: LiveCaptions.backendKind === modelData.id
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colLayer1
                            colBackgroundHover: LiveCaptions.backendKind === modelData.id
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colLayer1Hover
                            colText: LiveCaptions.backendKind === modelData.id
                                ? Appearance.colors.colOnLayer1
                                : Appearance.colors.colSubtext
                            downAction: () => LiveCaptions.setBackendKind(modelData.id)
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: LiveCaptions.backendKind === "asr"
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    text: Translation.tr("Streaming ASR currently supports English, Italian, and German. Unsupported languages fall back to English.")
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: LiveCaptions.backendKind === "whisper"
                    text: Translation.tr("Tweaks")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: LiveCaptions.backendKind === "whisper"
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    text: Translation.tr("Realtime is the most aggressive low-latency mode. The slower presets wait longer before trusting or replacing words.")
                }

                Flow {
                    Layout.fillWidth: true
                    visible: LiveCaptions.backendKind === "whisper"
                    spacing: 8

                    Repeater {
                        model: LiveCaptions.tuningPresetOptions
                        delegate: DialogButton {
                            required property var modelData
                            buttonText: modelData.label
                            colBackground: LiveCaptions.tuningPreset === modelData.id
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colLayer1
                            colBackgroundHover: LiveCaptions.tuningPreset === modelData.id
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colLayer1Hover
                            colText: LiveCaptions.tuningPreset === modelData.id
                                ? Appearance.colors.colOnLayer1
                                : Appearance.colors.colSubtext
                            downAction: () => LiveCaptions.setTuningPreset(modelData.id)
                        }
                    }
                }

                // Speech language section
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Speech language")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: root.speechQuickLanguages
                        delegate: DialogButton {
                            required property var modelData
                            buttonText: modelData.label
                            colBackground: LiveCaptions.preferredLanguage === modelData.id
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colLayer1
                            colBackgroundHover: LiveCaptions.preferredLanguage === modelData.id
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colLayer1Hover
                            colText: LiveCaptions.preferredLanguage === modelData.id
                                ? Appearance.colors.colOnLayer1
                                : Appearance.colors.colSubtext
                            downAction: () => LiveCaptions.setPreferredLanguage(modelData.id)
                        }
                    }
                }

                StyledComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "language"
                    textRole: "label"
                    model: [{ id: "", label: Translation.tr("More languages") }].concat(root.speechMoreLanguages)
                    currentIndex: Math.max(0, root.speechMoreLanguages.findIndex(lang => lang.id === LiveCaptions.preferredLanguage) + 1)
                    onActivated: index => {
                        if (index > 0 && index <= root.speechMoreLanguages.length)
                            LiveCaptions.setPreferredLanguage(root.speechMoreLanguages[index - 1].id)
                    }
                }

                // Translate to (only when translation overlay is open)
                StyledText {
                    Layout.fillWidth: true
                    visible: root.translationOverlayOpen
                    text: Translation.tr("Translate to")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                Flow {
                    Layout.fillWidth: true
                    visible: root.translationOverlayOpen
                    spacing: 8

                    Repeater {
                        model: root.targetQuickLanguages
                        delegate: DialogButton {
                            required property var modelData
                            buttonText: modelData.label
                            colBackground: LiveCaptions.targetLanguage === modelData.id
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colLayer1
                            colBackgroundHover: LiveCaptions.targetLanguage === modelData.id
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colLayer1Hover
                            colText: LiveCaptions.targetLanguage === modelData.id
                                ? Appearance.colors.colOnLayer1
                                : Appearance.colors.colSubtext
                            downAction: () => LiveCaptions.setTargetLanguage(modelData.id)
                        }
                    }
                }

                StyledComboBox {
                    Layout.fillWidth: true
                    visible: root.translationOverlayOpen
                    buttonIcon: "translate"
                    textRole: "label"
                    model: [{ id: "", label: Translation.tr("More languages") }].concat(root.targetMoreLanguages)
                    currentIndex: Math.max(0, root.targetMoreLanguages.findIndex(lang => lang.id === LiveCaptions.targetLanguage) + 1)
                    onActivated: index => {
                        if (index > 0 && index <= root.targetMoreLanguages.length)
                            LiveCaptions.setTargetLanguage(root.targetMoreLanguages[index - 1].id)
                    }
                }

                Item { implicitHeight: 0 }
            }
        }
    }
}
