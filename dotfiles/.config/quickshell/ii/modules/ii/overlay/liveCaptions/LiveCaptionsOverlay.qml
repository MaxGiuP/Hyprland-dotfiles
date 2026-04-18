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
    readonly property bool singleStreamMode: LiveCaptions.backendKind === "asr"
    function colorToHex(color, alpha = 1.0) {
        const clamp = value => Math.max(0, Math.min(255, Math.round(value * 255)))
        return `#${clamp(alpha).toString(16).padStart(2, "0")}${clamp(color.r).toString(16).padStart(2, "0")}${clamp(color.g).toString(16).padStart(2, "0")}${clamp(color.b).toString(16).padStart(2, "0")}`
    }
    function asrMarkup() {
        const committedLines = String(LiveCaptions.stableText ?? "")
            .split(/\n+/)
            .map(line => line.trim())
            .filter(line => line.length > 0)
            .slice(-3)
        const unstable = String(LiveCaptions.unstableText ?? "").trim()
        const colors = ["#FFFFFF", "#E8EEF7", "#FFF2DA"]
        const parts = []

        for (let i = 0; i < committedLines.length; ++i) {
            const color = colors[i % colors.length]
            parts.push(`<span style="color:${color};">${LiveCaptions.escapeRichText(committedLines[i])}</span>`)
        }

        if (unstable.length > 0)
            parts.push(`<span style="color:#CCFFFFFF;">${LiveCaptions.escapeRichText(unstable)}</span>`)

        if (parts.length > 0)
            return parts.join("<br>")

        return LiveCaptions.active
            ? LiveCaptions.escapeRichText(Translation.tr("Listening…"))
            : LiveCaptions.escapeRichText(Translation.tr("Not running"))
    }

    contentItem: Rectangle {
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
                color: "white"
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
            spacing: root.singleStreamMode ? 0 : (liveTailText.visible && stableText.visible ? 4 : 0)

            Text {
                id: stableText
                width: parent.width
                visible: text.trim().length > 0
                wrapMode: Text.WordWrap
                renderType: Text.QtRendering
                verticalAlignment: Text.AlignTop
                color: "white"
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
                visible: !root.singleStreamMode && (text.trim().length > 0 || !stableText.visible)
                wrapMode: Text.WordWrap
                renderType: Text.QtRendering
                verticalAlignment: Text.AlignTop
                color: stableText.visible ? "#CCFFFFFF" : "white"
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

        FontMetrics {
            id: stableMetrics
            font: stableText.font
        }
    }
}
