import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    title: Translation.tr("Live Captions")
    showCenterButton: true
    minimumWidth: 320
    minimumHeight: 80
    readonly property bool singleStreamMode: LiveCaptions.backendKind === "asr"
    function asrMarkup() {
        const committedLines = String(LiveCaptions.stableText ?? "")
            .split(/\n+/)
            .map(line => line.trim())
            .filter(line => line.length > 0)
            .slice(-3)
        const unstable = String(LiveCaptions.unstableText ?? "").trim()
        const parts = []

        for (let i = 0; i < committedLines.length; ++i) {
            parts.push(`<span style="color:${bubble.foreground};">${LiveCaptions.escapeRichText(committedLines[i])}</span>`)
        }

        if (unstable.length > 0)
            parts.push(`<span style="color:${bubble.secondaryForeground};">${LiveCaptions.escapeRichText(unstable)}</span>`)

        if (parts.length > 0)
            return parts.join("<br>")

        return LiveCaptions.active
            ? LiveCaptions.escapeRichText(Translation.tr("Listening…"))
            : LiveCaptions.escapeRichText(Translation.tr("Not running"))
    }

    contentItem: CaptionBubble {
        id: bubble
        implicitWidth: 560
        readonly property real minBubbleHeight: stableMetrics.height * 2.6 + 28
        readonly property real maxBubbleHeight: stableMetrics.height * 5.6 + 34
        readonly property real singleStreamHeight: stableMetrics.height * 3.7 + 28
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
                wrapMode: Text.Wrap
                renderType: Text.QtRendering
                verticalAlignment: Text.AlignTop
                color: bubble.foreground
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.large
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
                visible: !root.singleStreamMode
                width: parent.width
                y: Math.min(0, parent.height - height)
                spacing: root.singleStreamMode ? 0 : (liveTailText.visible && stableText.visible ? 4 : 0)

                Text {
                    id: stableText
                    width: parent.width
                    visible: text.trim().length > 0
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    renderType: Text.QtRendering
                    verticalAlignment: Text.AlignTop
                    color: bubble.foreground
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.hintingPreference: Font.PreferDefaultHinting
                    lineHeightMode: Text.ProportionalHeight
                    lineHeight: 1.12
                    text: (LiveCaptions.visibleStableText ?? "").trim()
                }

                Text {
                    id: liveTailText
                    width: parent.width
                    textFormat: Text.PlainText
                    visible: !root.singleStreamMode && (text.trim().length > 0 || !stableText.visible)
                    wrapMode: Text.Wrap
                    renderType: Text.QtRendering
                    verticalAlignment: Text.AlignTop
                    color: stableText.visible ? bubble.secondaryForeground : bubble.foreground
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.hintingPreference: Font.PreferDefaultHinting
                    lineHeightMode: Text.ProportionalHeight
                    lineHeight: 1.12
                    text: {
                        const tail = (LiveCaptions.visibleUnstableText ?? "").trim()
                        if (tail.length > 0)
                            return tail
                        if (stableText.visible)
                            return ""
                        return LiveCaptions.active
                            ? Translation.tr("Listening…")
                            : Translation.tr("Not running")
                    }
                }
            }
        }

        FontMetrics {
            id: stableMetrics
            font: stableText.font
        }
    }
}
