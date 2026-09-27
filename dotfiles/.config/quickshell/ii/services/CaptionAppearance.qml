pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

Singleton {
    id: root

    readonly property real textScale: root.normalizedScale(Persistent.states.captionAppearance.textScale)
    readonly property bool sentenceHighlighting: Persistent.states.captionAppearance.sentenceHighlighting
    readonly property string translationGranularity: Persistent.states.captionAppearance.translationGranularity === "sentence" ? "sentence" : "phrase"
    readonly property int mainTextPixelSize: Math.round(Appearance.font.pixelSize.large * root.textScale)

    function normalizedScale(value) {
        const numeric = Number(value)
        if (!isFinite(numeric))
            return 1.0
        return Math.round(Math.max(0.75, Math.min(2.0, numeric)) * 20) / 20
    }

    function setTextScale(value) {
        Persistent.states.captionAppearance.textScale = root.normalizedScale(value)
    }

    function setSentenceHighlighting(enabled) {
        Persistent.states.captionAppearance.sentenceHighlighting = Boolean(enabled)
    }

    function setTranslationGranularity(value) {
        Persistent.states.captionAppearance.translationGranularity = value === "sentence" ? "sentence" : "phrase"
    }
}
