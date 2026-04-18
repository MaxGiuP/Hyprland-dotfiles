import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    title: Translation.tr("Live Screen Translate")
    showCenterButton: true

    contentItem: Rectangle {
        implicitWidth: 520
        implicitHeight: controlsColumn.implicitHeight + 20
        radius: root.contentRadius
        color: Qt.rgba(0, 0, 0, 0.78)
        clip: true

        ColumnLayout {
            id: controlsColumn
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                visible: GlobalStates.overlayOpen
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: LiveScreenTranslation.summaryText
                    color: Appearance.colors.colSubtext
                }

                DialogButton {
                    buttonText: LiveScreenTranslation.active ? Translation.tr("Stop") : Translation.tr("Start")
                    downAction: () => LiveScreenTranslation.toggleRunning()
                }

                DialogButton {
                    buttonText: Translation.tr("Set region")
                    downAction: () => LiveScreenTranslation.selectRegion()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: GlobalStates.overlayOpen
                wrapMode: Text.WordWrap
                color: LiveScreenTranslation.backendAvailable ? Appearance.colors.colSubtext : Appearance.colors.colError
                text: LiveScreenTranslation.backendAvailable
                    ? (LiveScreenTranslation.regionLabel.length > 0
                        ? Translation.tr("Region: %1").arg(LiveScreenTranslation.regionLabel)
                        : Translation.tr("No region selected yet."))
                    : LiveScreenTranslation.backendStatusText
            }

            Flow {
                Layout.fillWidth: true
                visible: GlobalStates.overlayOpen
                spacing: 8

                Repeater {
                    model: LiveScreenTranslation.targetLanguageOptions
                    delegate: DialogButton {
                        required property var modelData
                        buttonText: modelData.label
                        colBackground: LiveScreenTranslation.targetLanguage === modelData.id
                            ? Appearance.colors.colPrimaryContainer
                            : Appearance.colors.colLayer1
                        colBackgroundHover: LiveScreenTranslation.targetLanguage === modelData.id
                            ? Appearance.colors.colPrimaryContainer
                            : Appearance.colors.colLayer1Hover
                        colText: LiveScreenTranslation.targetLanguage === modelData.id
                            ? Appearance.colors.colOnLayer1
                            : Appearance.colors.colSubtext
                        downAction: () => LiveScreenTranslation.setTargetLanguage(modelData.id)
                    }
                }
            }

            DialogButton {
                visible: GlobalStates.overlayOpen && LiveScreenTranslation.regionLabel.length > 0
                buttonText: Translation.tr("Clear region")
                downAction: () => LiveScreenTranslation.clearRegion()
            }

            Rectangle {
                Layout.fillWidth: true
                visible: LiveScreenTranslation.status === "error" && LiveScreenTranslation.statusMessage.length > 0
                radius: Appearance.rounding.small
                color: Qt.rgba(0.8, 0.1, 0.1, 0.18)
                border.width: 1
                border.color: Appearance.colors.colError
                implicitHeight: errorText.implicitHeight + 14

                StyledText {
                    id: errorText
                    anchors.fill: parent
                    anchors.margins: 7
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: LiveScreenTranslation.statusMessage
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Appearance.rounding.small
                color: Qt.rgba(0, 0, 0, 0.18)
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                implicitHeight: translationText.implicitHeight + sourceText.implicitHeight + 26

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Text {
                        id: translationText
                        width: parent.width
                        wrapMode: Text.WordWrap
                        renderType: Text.QtRendering
                        color: Appearance.colors.colPrimary
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.large
                        text: {
                            const translated = String(LiveScreenTranslation.translatedText ?? "").trim()
                            if (translated.length > 0)
                                return translated
                            if (LiveScreenTranslation.active)
                                return Translation.tr("Watching for text…")
                            return Translation.tr("Screen translation stopped.")
                        }
                    }

                    Text {
                        id: sourceText
                        visible: GlobalStates.overlayOpen
                        width: parent.width
                        wrapMode: Text.WordWrap
                        renderType: Text.QtRendering
                        color: "#CCFFFFFF"
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.normal
                        text: String(LiveScreenTranslation.ocrText ?? "").trim()
                    }
                }
            }
        }
    }
}
