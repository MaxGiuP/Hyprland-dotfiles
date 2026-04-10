import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

ColumnLayout {
    id: root
    required property bool isSink
    readonly property list<var> appPwNodes: isSink ? Audio.outputAppNodes : Audio.inputAppNodes
    readonly property list<var> devices: isSink ? Audio.selectableOutputDevices : Audio.selectableInputDevices
    readonly property bool hasApps: appPwNodes.length > 0
    spacing: 16

    StyledFlickable {
        Layout.fillHeight: true
        Layout.fillWidth: true
        clip: true
        contentHeight: appListColumn.implicitHeight
        contentWidth: width

        ColumnLayout {
            id: appListColumn
            width: parent.width
            spacing: 6

            Repeater {
                model: root.appPwNodes
                delegate: VolumeMixerEntry {
                    Layout.fillWidth: true
                    required property var modelData
                    node: modelData
                }
            }

            PagePlaceholder {
                icon: "widgets"
                title: Translation.tr("No applications")
                shown: !root.hasApps
                shape: MaterialShape.Shape.Cookie7Sided
            }
        }
    }

    StyledComboBox {
        id: deviceSelector
        Layout.fillHeight: false
        Layout.fillWidth: true
        Layout.bottomMargin: 6
        model: root.devices.map(node => Audio.friendlyDeviceName(node))
        currentIndex: root.devices.findIndex(item => {
            if (root.isSink) {
                return Audio.isCurrentDefaultSink(item)
            } else {
                return Audio.isCurrentDefaultSource(item)
            }
        })
        onActivated: (index) => {
            print(index)
            const item = root.devices[index]
            if (root.isSink) {
                Audio.setDefaultSink(item)
            } else {
                Audio.setDefaultSource(item)
            }
        }
    }
}
