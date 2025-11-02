// =====================================
// SessionActionButton.qml  (clean final)
// Hover animates to circular primary and overrides keyboard focus
// =====================================
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RippleButton {
    id: button

    property string buttonIcon
    property string buttonText
    property bool keyboardDown: false
    property real size: 120

    // Active state: focused, pressed, or hovered
    readonly property bool activeVisual: button.focus || button.down || hover.active || keyboardDown

    // Visuals + animation
    buttonRadius: activeVisual ? size / 2 : Appearance.rounding.verylarge
    colBackground: activeVisual ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
    colBackgroundHover: colBackground
    colRipple: Appearance.colors.colPrimaryActive
    property color colText: activeVisual ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0

    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
    background.implicitHeight: size
    background.implicitWidth: size

    Behavior on buttonRadius {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Keyboard press behavior
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            keyboardDown = true
            button.clicked()
            event.accepted = true
        }
    }
    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            keyboardDown = false
            event.accepted = true
        }
    }

    // Walk up ancestors to find sessionRoot methods
    function sessionRoot() {
        var p = button.parent;
        while (p) {
            if (p.hasOwnProperty("mouseTakeFocus") && p.hasOwnProperty("mouseReleaseFocus"))
                return p;
            p = p.parent;
        }
        return null;
    }

    // Hover behavior: take focus on enter, release on exit
    HoverHandler {
        id: hover
        onActiveChanged: {
            const sr = button.sessionRoot();
            if (!sr) return;
            if (active) sr.mouseTakeFocus(button);
            else        sr.mouseReleaseFocus();
        }
    }

    contentItem: MaterialSymbol {
        anchors.fill: parent
        color: button.colText
        horizontalAlignment: Text.AlignHCenter
        iconSize: 45
        text: buttonIcon
    }

    StyledToolTip { content: buttonText }
}
