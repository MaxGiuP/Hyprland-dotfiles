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
                { id: "phrase", label: Translation.tr("Short phrases") },
                { id: "sentence", label: Translation.tr("Whole sentences") }
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
        text: Translation.tr("Short phrases share matching colours across both panes. Whole sentences keep more context for translation. Changing this restarts active translation; text size and colours update immediately.")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
}
