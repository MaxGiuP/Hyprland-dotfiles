import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    title: Translation.tr("Translation")
    showCenterButton: true
    readonly property bool singleStreamMode: LiveCaptions.backendKind === "asr"
    function colorToHex(color, alpha = 1.0) {
        const clamp = value => Math.max(0, Math.min(255, Math.round(value * 255)))
        return `#${clamp(alpha).toString(16).padStart(2, "0")}${clamp(color.r).toString(16).padStart(2, "0")}${clamp(color.g).toString(16).padStart(2, "0")}${clamp(color.b).toString(16).padStart(2, "0")}`
    }
    function asrMarkup() {
        const committed = String(LiveCaptions.translatedStableText ?? "").trim()
        const unstable = String(LiveCaptions.translatedUnstableText ?? "").trim()
        const parts = []

        if (committed.length > 0)
            parts.push(`<span style="color:${root.colorToHex(Appearance.colors.colPrimary)};">${LiveCaptions.escapeRichText(committed).replace(/\n/g, "<br>")}</span>`)
        if (unstable.length > 0)
            parts.push(`<span style="color:${root.colorToHex(Appearance.colors.colPrimary, 0.78)};">${LiveCaptions.escapeRichText(unstable)}</span>`)

        if (parts.length > 0)
            return parts.join("<br>")

        return LiveCaptions.escapeRichText((LiveCaptions.visibleTranslatedTranscriptText ?? "").trim())
    }

    contentItem: Rectangle {
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
        color: Qt.rgba(0, 0, 0, 0.78)
        clip: true

        Behavior on implicitHeight {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        Item {
            id: singleStreamViewport
            visible: root.singleStreamMode
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
                wrapMode: Text.WordWrap
                renderType: Text.QtRendering
                verticalAlignment: Text.AlignTop
                color: Appearance.colors.colPrimary
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.large
                font.hintingPreference: Font.PreferDefaultHinting
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 1.12
                text: root.asrMarkup()
            }
        }

        Column {
            id: textColumn
            visible: !root.singleStreamMode
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 12
                rightMargin: 12
                topMargin: 12
            }
            spacing: root.singleStreamMode ? 0 : (previewTranslationText.visible && stableTranslationText.visible ? 4 : 0)

            Text {
                id: stableTranslationText
                width: parent.width
                visible: text.trim().length > 0
                wrapMode: Text.WordWrap
                renderType: Text.QtRendering
                verticalAlignment: Text.AlignTop
                color: Appearance.colors.colPrimary
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.large
                font.hintingPreference: Font.PreferDefaultHinting
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 1.12
                text: (LiveCaptions.visibleTranslatedStableText ?? "").trim()
            }

            Text {
                id: previewTranslationText
                width: parent.width
                visible: !root.singleStreamMode && text.trim().length > 0
                wrapMode: Text.WordWrap
                renderType: Text.QtRendering
                verticalAlignment: Text.AlignTop
                color: Qt.rgba(
                    Appearance.colors.colPrimary.r,
                    Appearance.colors.colPrimary.g,
                    Appearance.colors.colPrimary.b,
                    0.78
                )
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.large
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

        FontMetrics {
            id: translationMetrics
            font: stableTranslationText.font
        }
    }
}
