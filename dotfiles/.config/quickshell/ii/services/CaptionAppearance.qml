pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

Singleton {
    id: root

    readonly property real textScale: root.normalizedScale(Persistent.states.captionAppearance.textScale)
    readonly property bool sentenceHighlighting: Persistent.states.captionAppearance.sentenceHighlighting
    readonly property string translationGranularity: Persistent.states.captionAppearance.translationGranularity === "phrase" ? "phrase" : "sentence"
    readonly property string translationStyle: Persistent.states.captionAppearance.translationStyle === "literal" ? "literal" : "natural"
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
        Persistent.states.captionAppearance.translationQualityVersion = 1
        Persistent.states.captionAppearance.translationGranularity = value === "phrase" ? "phrase" : "sentence"
    }

    function setTranslationStyle(value) {
        Persistent.states.captionAppearance.translationStyle = value === "literal" ? "literal" : "natural"
    }

    function migrateTranslationQuality() {
        if (!Persistent.ready || (Persistent.states.captionAppearance.translationQualityVersion ?? 0) >= 1)
            return
        // Restore sentence context once for earlier installations. A later
        // explicit choice of short phrases is retained across shell reloads.
        Persistent.states.captionAppearance.translationQualityVersion = 1
        Persistent.states.captionAppearance.translationGranularity = "sentence"
    }

    Connections {
        target: Persistent
        function onReadyChanged() { root.migrateTranslationQuality() }
    }

    Component.onCompleted: root.migrateTranslationQuality()
}
