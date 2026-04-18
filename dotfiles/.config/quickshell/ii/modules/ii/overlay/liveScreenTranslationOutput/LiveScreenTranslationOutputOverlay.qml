import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    title: Translation.tr("Screen Translation")
    showCenterButton: true

    contentItem: Rectangle {
        implicitWidth: 520
        implicitHeight: translationText.implicitHeight + sourceText.implicitHeight + (sourceText.visible ? 32 : 20)
        radius: root.contentRadius
        color: Qt.rgba(0, 0, 0, 0.78)
        clip: true

        Column {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: 12
            }
            spacing: 6

            Text {
                id: translationText
                width: parent.width
                wrapMode: Text.WordWrap
                renderType: Text.QtRendering
                color: {
                    if (LiveScreenTranslation.status === "error")
                        return Appearance.colors.colError
                    return Appearance.colors.colPrimary
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
                wrapMode: Text.WordWrap
                renderType: Text.QtRendering
                color: "#99FFFFFF"
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: String(LiveScreenTranslation.ocrText ?? "").trim()
            }
        }
    }
}
