import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls

/**
 * Material 3 styled SpinBox component.
 */
SpinBox {
    id: root

    property real baseHeight: 35
    property real radius: Appearance.rounding.normal
    property real innerButtonRadius: Appearance.rounding.unsharpenmore
    property real fieldPadding: 10
    readonly property color frameColor: activeFocus
        ? Appearance.colors.colPrimary
        : Appearance.colors.colOutlineVariant
    readonly property color fieldColor: activeFocus
        ? Appearance.colors.colLayer2Hover
        : Appearance.colors.colLayer2
    readonly property color stepperColor: activeFocus
        ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer2, 0.55)
        : Appearance.colors.colSecondaryContainer
    readonly property color stepperHoverColor: activeFocus
        ? ColorUtils.mix(Appearance.colors.colPrimaryContainerHover, Appearance.colors.colLayer2Hover, 0.5)
        : Appearance.colors.colSecondaryContainerHover
    readonly property color stepperPressedColor: activeFocus
        ? ColorUtils.mix(Appearance.colors.colPrimaryContainerActive, Appearance.colors.colLayer2Active, 0.5)
        : Appearance.colors.colSecondaryContainerActive
    editable: true

    opacity: root.enabled ? 1 : 0.4
    implicitWidth: contentItem.implicitWidth + root.baseHeight * 2
    implicitHeight: root.baseHeight

    background: Rectangle {
        color: root.fieldColor
        radius: root.radius
        border.width: 1
        border.color: root.frameColor

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    contentItem: Item {
        implicitHeight: root.baseHeight
        implicitWidth: Math.max(labelText.implicitWidth + root.fieldPadding * 2, 72)

        StyledTextInput {
            id: labelText
            anchors.fill: parent
            anchors.leftMargin: root.fieldPadding
            anchors.rightMargin: root.fieldPadding
            text: root.value // displayText would make the numbers weird like 1,000 instead of 1000
            color: Appearance.colors.colOnLayer2
            font.family: Appearance.font.family.numbers
            font.variableAxes: Appearance.disableVariableFonts ? ({}) : Appearance.font.variableAxes.numbers
            font.pixelSize: Appearance.font.pixelSize.small
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            validator: root.validator
            onTextChanged: {
                const nextValue = parseFloat(text);
                if (!Number.isNaN(nextValue)) {
                    root.value = nextValue;
                }
            }
        }
    }

    down.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topLeftRadius: root.radius
        bottomLeftRadius: root.radius
        topRightRadius: root.innerButtonRadius
        bottomRightRadius: root.innerButtonRadius

        color: root.down.pressed
            ? root.stepperPressedColor
            : root.down.hovered
                ? root.stepperHoverColor
                : root.stepperColor
        border.width: 1
        border.color: ColorUtils.transparentize(root.frameColor, 0.15)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "remove"
            iconSize: 18
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    up.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            right: parent.right
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topRightRadius: root.radius
        bottomRightRadius: root.radius
        topLeftRadius: root.innerButtonRadius
        bottomLeftRadius: root.innerButtonRadius

        color: root.up.pressed
            ? root.stepperPressedColor
            : root.up.hovered
                ? root.stepperHoverColor
                : root.stepperColor
        border.width: 1
        border.color: ColorUtils.transparentize(root.frameColor, 0.15)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: 18
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
}
