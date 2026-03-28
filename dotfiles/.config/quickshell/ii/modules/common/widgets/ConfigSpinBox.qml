import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RowLayout {
    id: root
    property string text: ""
    property string icon
    property real value: 0
    property real stepSize: 1
    property real from: 0
    property real to: 100
    property bool spinBoxReady: false
    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    RowLayout {
        spacing: 10
        OptionalMaterialSymbol {
            icon: root.icon
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
            opacity: root.enabled ? 1 : 0.4
        }
    }

    Loader {
        id: spinBoxLoader
        Layout.fillWidth: false

        sourceComponent: styledSpinBoxComponent

        onItemChanged: {
            root.spinBoxReady = false
            if (item) {
                Qt.callLater(() => {
                    if (spinBoxLoader.item)
                        root.spinBoxReady = true
                })
            }
        }
    }

    Binding {
        when: spinBoxLoader.item && root.spinBoxReady
        target: spinBoxLoader.item
        property: "value"
        value: root.value
    }

    Binding {
        when: spinBoxLoader.item
        target: spinBoxLoader.item
        property: "stepSize"
        value: root.stepSize
    }

    Binding {
        when: spinBoxLoader.item
        target: spinBoxLoader.item
        property: "from"
        value: root.from
    }

    Binding {
        when: spinBoxLoader.item
        target: spinBoxLoader.item
        property: "to"
        value: root.to
    }

    Connections {
        target: spinBoxLoader.item
        enabled: root.spinBoxReady

        function onValueChanged() {
            if (spinBoxLoader.item && root.value !== spinBoxLoader.item.value)
                root.value = spinBoxLoader.item.value
        }
    }

    Component {
        id: styledSpinBoxComponent

        StyledSpinBox {
            Layout.fillWidth: false
        }
    }
}
