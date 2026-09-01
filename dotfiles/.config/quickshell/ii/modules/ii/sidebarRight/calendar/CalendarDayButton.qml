import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button
    property string day
    property int isToday
    property bool bold
    property bool selected: false
    property int eventCount: 0
    property int taskCount: 0
    signal dayClicked()

    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 38
    implicitHeight: 38

    // Keep the 38px hit target, but use a compact state indicator so the
    // selection does not read as a large pill in the calendar grid.
    toggled: false
    buttonRadius: width / 2
    onClicked: {
        if (button.enabled) {
            dayClicked();
        }
    }

    contentItem: Item {
        Rectangle {
            id: dayStateIndicator
            anchors.centerIn: parent
            width: 28
            height: 28
            radius: width / 2
            antialiasing: true
            color: button.selected ? Appearance.colors.colPrimaryContainer : "transparent"
            border.width: button.isToday == 1 ? 1.5 : 0
            border.color: Appearance.colors.colPrimary

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            anchors.fill: parent
            text: button.day
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.weight: button.bold || button.selected || button.isToday == 1 ? Font.DemiBold : Font.Normal
            color: button.selected
                ? Appearance.colors.colOnPrimaryContainer
                : button.isToday == 1
                    ? Appearance.colors.colPrimary
                    : button.isToday == 0
                        ? Appearance.colors.colOnLayer1
                        : Appearance.colors.colOutlineVariant

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    Rectangle {
        visible: (eventCount + taskCount) > 0 && isToday >= 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        width: 12
        height: 3
        radius: 2
        color: button.selected
            ? Appearance.colors.colOnPrimaryContainer
            : taskCount > 0
                ? Appearance.colors.colSecondary
                : Appearance.colors.colTertiary
    }
}
