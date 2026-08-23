import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    property bool pending: false
    property bool resetVisible: true
    property string applyText: Translation.tr("Apply changes")
    property string applyIcon: "check"
    property string cleanText: Translation.tr("Up to date")
    property string pendingText: Translation.tr("Changes not applied")

    signal applyRequested()
    signal resetRequested()

    Layout.fillWidth: true
    implicitHeight: actionRow.implicitHeight + 16
    radius: Appearance.rounding.small
    color: root.pending ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    RowLayout {
        id: actionRow
        anchors.fill: parent
        anchors.margins: 8
        spacing: 10

        MaterialSymbol {
            text: root.pending ? "pending" : "check_circle"
            iconSize: 20
            fill: 1
            color: root.pending ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            text: root.pending ? root.pendingText : root.cleanText
            color: root.pending ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: root.pending ? Font.Medium : Font.Normal
            elide: Text.ElideRight
        }

        IconToolbarButton {
            visible: root.resetVisible
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            text: "restart_alt"
            enabled: root.enabled
            onClicked: root.resetRequested()

            StyledToolTip {
                text: Translation.tr("Reset to defaults")
            }
        }

        RippleButtonWithIcon {
            Layout.preferredWidth: Math.max(150, implicitWidth)
            Layout.preferredHeight: 36
            enabled: root.enabled && root.pending
            materialIcon: root.applyIcon
            mainText: root.applyText
            onClicked: root.applyRequested()
        }
    }
}
