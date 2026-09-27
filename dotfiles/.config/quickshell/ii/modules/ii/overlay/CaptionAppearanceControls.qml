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
            text: Translation.tr("Match sentence colours")
            color: Appearance.colors.colOnLayer1
        }

        StyledSwitch {
            checked: CaptionAppearance.sentenceHighlighting
            Accessible.name: Translation.tr("Match sentence colours")
            onToggled: CaptionAppearance.setSentenceHighlighting(checked)
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        wrapMode: Text.WordWrap
        text: Translation.tr("Matching source and translated sentences share a colour. These settings apply to captions and screen translation.")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
}
