pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    default property alias contentData: combo.data

    property string buttonIcon: ""
    property real buttonRadius: combo.height / 2
    property color colBackground: Appearance.colors.colSecondaryContainer
    property color colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    property color colBackgroundActive: Appearance.colors.colSecondaryContainerActive

    property alias model: combo.model
    property alias currentIndex: combo.currentIndex
    property alias textRole: combo.textRole
    property alias valueRole: combo.valueRole
    property alias editable: combo.editable
    property alias font: combo.font
    property alias popup: combo.popup
    readonly property alias currentText: combo.currentText
    readonly property alias displayText: combo.displayText
    readonly property alias down: combo.down
    readonly property alias hovered: combo.hovered

    signal activated(int index)

    implicitWidth: combo.implicitWidth
    implicitHeight: combo.implicitHeight
    Layout.fillWidth: true

    ComboBox {
        id: combo
        anchors.fill: parent

        enabled: root.enabled
        implicitHeight: 40
        Layout.fillWidth: true

        onActivated: index => root.activated(index)

        background: Rectangle {
            radius: root.buttonRadius
            color: (combo.down && !combo.popup.visible)
                ? root.colBackgroundActive
                : combo.hovered
                    ? root.colBackgroundHover
                    : root.colBackground

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
            }
        }

        indicator: MaterialSymbol {
            x: combo.width - width - 16
            y: combo.height / 2 - height / 2
            text: "keyboard_arrow_down"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSecondaryContainer

            rotation: combo.popup.visible ? 180 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        contentItem: Item {
            implicitWidth: buttonLayout.implicitWidth
            implicitHeight: buttonLayout.implicitHeight

            RowLayout {
                id: buttonLayout
                anchors.fill: parent
                spacing: 8
                anchors.leftMargin: 16
                anchors.rightMargin: 16

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.buttonIcon.length > 0 || (
                        combo.currentIndex >= 0 &&
                        typeof combo.model[combo.currentIndex] === "object" &&
                        (combo.model[combo.currentIndex]?.icon?.length ?? 0) > 0
                    )
                    text: {
                        if (combo.currentIndex >= 0 && typeof combo.model[combo.currentIndex] === "object" && combo.model[combo.currentIndex]?.icon) {
                            return combo.model[combo.currentIndex].icon;
                        }
                        return root.buttonIcon;
                    }
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    color: Appearance.colors.colOnSecondaryContainer
                    text: combo.displayText
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        delegate: ItemDelegate {
            id: itemDelegate
            width: ListView.view ? ListView.view.width : combo.width
            implicitHeight: 40

            required property var model
            required property int index
            property color color: {
                if (combo.currentIndex === itemDelegate.index) {
                    if (itemDelegate.down) return Appearance.colors.colSecondaryContainerActive;
                    if (itemDelegate.hovered) return Appearance.colors.colSecondaryContainerHover;
                    return Appearance.colors.colSecondaryContainer;
                } else {
                    if (itemDelegate.down) return Appearance.colors.colLayer3Active;
                    if (itemDelegate.hovered) return Appearance.colors.colLayer3Hover;
                    return ColorUtils.transparentize(Appearance.colors.colLayer3);
                }
            }
            property color colText: (combo.currentIndex === itemDelegate.index)
                ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnLayer3

            background: Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: itemDelegate.color

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: Qt.PointingHandCursor
                }
            }

            contentItem: RowLayout {
                spacing: 8
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: Appearance.font.pixelSize.larger
                    visible: typeof itemDelegate.model === "object" && itemDelegate.model?.icon?.length > 0
                    text: itemDelegate.model?.icon ?? ""
                    iconSize: Appearance.font.pixelSize.larger
                    color: itemDelegate.colText
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Appearance.font.pixelSize.larger
                    color: itemDelegate.colText
                    text: typeof itemDelegate.model === "object"
                        ? itemDelegate.model[combo.textRole]
                        : itemDelegate.model
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        popup: Popup {
            y: combo.height + 4
            width: combo.width
            height: Math.min(listView.contentHeight + topPadding + bottomPadding, 300)
            padding: 8

            enter: Transition {
                PropertyAnimation {
                    properties: "opacity"
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            exit: Transition {
                PropertyAnimation {
                    properties: "opacity"
                    to: 0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            background: Item {
                StyledRectangularShadow {
                    target: popupBackground
                }

                Rectangle {
                    id: popupBackground
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: Appearance.m3colors.m3surfaceContainerHigh
                }
            }

            contentItem: StyledListView {
                id: listView
                clip: true
                implicitHeight: contentHeight
                spacing: 2
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.highlightedIndex
            }
        }
    }
}
