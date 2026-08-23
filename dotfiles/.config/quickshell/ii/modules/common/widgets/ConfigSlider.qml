import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import qs.services

RowLayout {
    id: root
    Layout.fillWidth: true
    implicitHeight: 40
    spacing: 12
    Layout.leftMargin: 4
    Layout.rightMargin: 4

    property string text: ""
    property string buttonIcon: ""
    property alias value: slider.value
    property alias stopIndicatorValues: slider.stopIndicatorValues
    property bool usePercentTooltip: true
    property real from: slider.from
    property real to: slider.to
    property real textWidth: 120

    RowLayout {
        id: row
        Layout.preferredWidth: root.textWidth
        Layout.maximumWidth: root.textWidth
        spacing: 8

        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            iconSize: 19
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
            elide: Text.ElideRight
        }
    }
    
    StyledSlider {
        id: slider
        Layout.fillWidth: true
        Layout.minimumWidth: 120
        configuration: StyledSlider.Configuration.XS
        usePercentTooltip: root.usePercentTooltip
        value: root.value
        from: root.from
        to: root.to
    }
}
