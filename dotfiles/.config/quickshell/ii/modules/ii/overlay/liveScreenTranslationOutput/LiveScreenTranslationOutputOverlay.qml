import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    title: Translation.tr("Screen Translation")
    showCenterButton: true
    minimumWidth: 320
    minimumHeight: 80

    contentItem: CaptionBubble {
        id: bubble
        anchors.fill: parent
        implicitWidth: 520
        implicitHeight: Math.min(root.screenHeight * 0.6, outputColumn.implicitHeight + 24)
        radius: root.contentRadius

        StyledFlickable {
            anchors.fill: parent
            anchors.margins: 12
            contentHeight: outputColumn.implicitHeight
            clip: true

            Column {
                id: outputColumn
                width: parent.width
                spacing: 6

                Text {
                    id: translationText
                    width: parent.width
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    renderType: Text.QtRendering
                    color: {
                        if (LiveScreenTranslation.status === "error")
                            return Appearance.colors.colError
                        return bubble.translationForeground
                    }
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.large
                    text: {
                        if (LiveScreenTranslation.status === "error")
                            return LiveScreenTranslation.statusMessage || Translation.tr("OCR error")
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
                    visible: {
                        const src = String(LiveScreenTranslation.ocrText ?? "").trim()
                        return src.length > 0 && LiveScreenTranslation.status !== "error"
                    }
                    width: parent.width
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    renderType: Text.QtRendering
                    color: bubble.secondaryForeground
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: String(LiveScreenTranslation.ocrText ?? "").trim()
                }
            }
        }
    }
}
