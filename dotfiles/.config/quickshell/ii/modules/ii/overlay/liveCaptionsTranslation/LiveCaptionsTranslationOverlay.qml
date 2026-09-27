import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    title: CaptionAppearance.translationStyle === "literal"
        ? Translation.tr("Literal translation") : Translation.tr("Translation")
    showCenterButton: true
    minimumWidth: 320
    minimumHeight: 80
    readonly property bool translationFailed: (LiveCaptions.translationError ?? "").length > 0
    readonly property bool showSentenceColors: CaptionAppearance.sentenceHighlighting
        && LiveCaptions.translating && LiveCaptions.translationSegments.length > 0 && !root.translationFailed
    readonly property bool singleStreamMode: LiveCaptions.backendKind === "asr"
    function asrMarkup() {
        const committed = String(LiveCaptions.translatedStableText ?? "").trim()
        const unstable = String(LiveCaptions.translatedUnstableText ?? "").trim()
        const parts = []

        if (committed.length > 0)
            parts.push(`<span style="color:${bubble.translationForeground};">${LiveCaptions.escapeRichText(committed).replace(/\n/g, "<br>")}</span>`)
        if (unstable.length > 0)
            parts.push(`<span style="color:${bubble.secondaryForeground};">${LiveCaptions.escapeRichText(unstable)}</span>`)

        if (parts.length > 0)
            return parts.join("<br>")

        return LiveCaptions.escapeRichText((LiveCaptions.visibleTranslatedTranscriptText ?? "").trim())
    }

    contentItem: CaptionBubble {
        id: bubble
        implicitWidth: 560
        readonly property real minBubbleHeight: translationMetrics.height * 2.6 + 28
        readonly property real maxBubbleHeight: translationMetrics.height * 5.8 + 34
        readonly property real singleStreamHeight: translationMetrics.height * 3.7 + 28
        implicitHeight: root.singleStreamMode
            ? singleStreamHeight
            : Math.min(maxBubbleHeight, Math.max(minBubbleHeight, textColumn.implicitHeight + 24))
        anchors.fill: parent
        radius: root.contentRadius

        Behavior on implicitHeight {
            NumberAnimation {
                duration: Appearance.reduceMotion ? 0 : 160
                easing.type: Easing.OutCubic
            }
        }

        CaptionSentenceView {
            id: pairedView
            visible: root.showSentenceColors
            anchors.fill: parent
            anchors.margins: 12
            segments: LiveCaptions.translationSegments
            translated: true
            foreground: bubble.translationForeground
            fallbackText: LiveCaptions.active
                ? Translation.tr("Translating…") : Translation.tr("Not running")
        }

        Text {
            visible: root.translationFailed
            anchors.fill: parent
            anchors.margins: 12
            text: LiveCaptions.translationError ?? ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignVCenter
            color: bubble.translationForeground
            font.family: Appearance.font.family.main
            font.pixelSize: CaptionAppearance.mainTextPixelSize
        }

        Item {
            id: singleStreamViewport
            visible: root.singleStreamMode && !root.showSentenceColors && !root.translationFailed
            anchors.fill: parent
            anchors.margins: 12
            clip: true

            Text {
                id: singleStreamText
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                textFormat: Text.RichText
                wrapMode: Text.Wrap
                renderType: Text.QtRendering
                verticalAlignment: Text.AlignTop
                color: bubble.translationForeground
                font.family: Appearance.font.family.main
                font.pixelSize: CaptionAppearance.mainTextPixelSize
                font.hintingPreference: Font.PreferDefaultHinting
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 1.12
                text: root.asrMarkup()
            }
        }

        Item {
            anchors.fill: parent
            anchors.margins: 12
            clip: true

            Column {
                id: textColumn
                visible: !root.singleStreamMode && !root.showSentenceColors && !root.translationFailed
                width: parent.width
                y: Math.min(0, parent.height - height)
                spacing: root.singleStreamMode ? 0 : (previewTranslationText.visible && stableTranslationText.visible ? 4 : 0)

                Text {
                    id: stableTranslationText
                    width: parent.width
                    visible: text.trim().length > 0
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    renderType: Text.QtRendering
                    verticalAlignment: Text.AlignTop
                    color: bubble.translationForeground
                    font.family: Appearance.font.family.main
                    font.pixelSize: CaptionAppearance.mainTextPixelSize
                    font.hintingPreference: Font.PreferDefaultHinting
                    lineHeightMode: Text.ProportionalHeight
                    lineHeight: 1.12
                    text: (LiveCaptions.visibleTranslatedStableText ?? "").trim()
                }

                Text {
                    id: previewTranslationText
                    width: parent.width
                    textFormat: Text.PlainText
                    visible: !root.singleStreamMode && text.trim().length > 0
                    wrapMode: Text.Wrap
                    renderType: Text.QtRendering
                    verticalAlignment: Text.AlignTop
                    color: bubble.secondaryForeground
                    font.family: Appearance.font.family.main
                    font.pixelSize: CaptionAppearance.mainTextPixelSize
                    font.hintingPreference: Font.PreferDefaultHinting
                    lineHeightMode: Text.ProportionalHeight
                    lineHeight: 1.12
                    text: {
                        const preview = (LiveCaptions.visibleTranslatedUnstableText ?? "").trim()
                        if (preview.length > 0)
                            return preview
                        if (stableTranslationText.visible)
                            return ""
                        return (LiveCaptions.visibleTranslatedTranscriptText ?? "").trim()
                    }
                }
            }
        }

        FontMetrics {
            id: translationMetrics
            font: stableTranslationText.font
        }
    }
}
