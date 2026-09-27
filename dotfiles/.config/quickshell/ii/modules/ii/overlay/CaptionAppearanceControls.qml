pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    spacing: 8

    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Text appearance")
        font.bold: true
        color: Appearance.colors.colOnLayer1
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            wrapMode: Text.WordWrap
            text: Translation.tr("Text size")
            color: Appearance.colors.colSubtext
        }

        StyledText {
            text: `${Math.round(CaptionAppearance.textScale * 100)}%`
            color: Appearance.colors.colOnLayer1
        }

        DialogButton {
            buttonText: Translation.tr("Reset")
            enabled: CaptionAppearance.textScale !== 1.0
            downAction: () => CaptionAppearance.setTextScale(1.0)
        }
    }

    StyledSlider {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        from: 75
        to: 200
        stepSize: 5
        snapMode: Slider.SnapAlways
        value: CaptionAppearance.textScale * 100
        stopIndicatorValues: [75, 100, 150, 200]
        tooltipContent: `${Math.round(value)}%`
        Accessible.name: Translation.tr("Caption and translation text size")
        onMoved: CaptionAppearance.setTextScale(value / 100)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            wrapMode: Text.WordWrap
            text: Translation.tr("Match translation colours")
            color: Appearance.colors.colOnLayer1
        }

        StyledSwitch {
            checked: CaptionAppearance.sentenceHighlighting
            Accessible.name: Translation.tr("Match translation colours")
            onToggled: CaptionAppearance.setSentenceHighlighting(checked)
        }
    }

    Flow {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 8

        Repeater {
            model: [
                { id: "sentence", label: Translation.tr("Whole sentences") },
                { id: "phrase", label: Translation.tr("Short phrases") }
            ]
            delegate: DialogButton {
                required property var modelData
                buttonText: modelData.label
                colBackground: CaptionAppearance.translationGranularity === modelData.id
                    ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                colBackgroundHover: CaptionAppearance.translationGranularity === modelData.id
                    ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1Hover
                colText: Appearance.colors.colOnLayer1
                downAction: () => CaptionAppearance.setTranslationGranularity(modelData.id)
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        wrapMode: Text.WordWrap
        text: Translation.tr("Whole sentences keep more context for better translation. Short phrases use less context for smaller colour groups. This grouping applies to both styles. Completed prefixes stay coloured while new words wait for translation.")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Translation style")
        color: Appearance.colors.colOnLayer1
    }

    Flow {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 8

        Repeater {
            model: [
                { id: "natural", label: Translation.tr("Natural") },
                { id: "literal", label: Translation.tr("Literal (source order)") }
            ]
            delegate: DialogButton {
                required property var modelData
                buttonText: modelData.label
                colBackground: CaptionAppearance.translationStyle === modelData.id
                    ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                colBackgroundHover: CaptionAppearance.translationStyle === modelData.id
                    ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1Hover
                colText: Appearance.colors.colOnLayer1
                downAction: () => CaptionAppearance.setTranslationStyle(modelData.id)
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        wrapMode: Text.WordWrap
        text: Translation.tr("Literal translation keeps the original word order, so it may sound ungrammatical. It uses your installed local model and can be slower. Changing style or grouping restarts active translation; text size and colours update immediately.")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
}
