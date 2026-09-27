import QtQuick
import qs.services
import qs.modules.common

// Both panes receive the same segment list; never trim either language alone.
Item {
    id: root
    property var segments: []
    property bool translated: false
    property string fallbackText: ""
    property color foreground: Appearance.colors.colOnSurface
    readonly property string markup: CaptionSegments.markup(segments, translated)
    implicitHeight: sentenceText.implicitHeight
    clip: true

    Text {
        id: sentenceText
        width: parent.width
        y: Math.min(0, parent.height - height)
        textFormat: Text.RichText
        wrapMode: Text.Wrap
        renderType: Text.QtRendering
        color: root.foreground
        font.family: Appearance.font.family.main
        font.pixelSize: CaptionAppearance.mainTextPixelSize
        lineHeightMode: Text.ProportionalHeight
        lineHeight: 1.12
        text: root.markup.length > 0
            ? root.markup : LiveCaptions.escapeRichText(root.fallbackText)
    }
}
