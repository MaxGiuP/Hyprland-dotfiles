import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root

    property var target
    property real requestX: 0
    property real requestY: 0

    padding: 6
    modal: false
    focus: visible
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnPressOutsideParent

    x: {
        const maxX = Math.max(0, (parent?.width ?? 0) - width - 4);
        return Math.max(0, Math.min(requestX, maxX));
    }
    y: {
        const maxY = Math.max(0, (parent?.height ?? 0) - height - 4);
        return Math.max(0, Math.min(requestY, maxY));
    }

    function openAt(item, posX, posY) {
        const targetParent = root.parent ?? item?.parent ?? null;
        const mapped = (item && targetParent && item.mapToItem)
            ? item.mapToItem(targetParent, posX, posY)
            : ({ x: posX, y: posY });
        requestX = mapped.x;
        requestY = mapped.y;
        open();
    }

    readonly property bool hasSelection: String(target?.selectedText ?? "").length > 0
    readonly property bool canEdit: !(target?.readOnly ?? false)
    readonly property bool hasText: String(target?.text ?? "").length > 0

    background: Item {
        StyledRectangularShadow {
            target: popupBackground
        }

        Rectangle {
            id: popupBackground
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
        }
    }

    contentItem: ColumnLayout {
        spacing: 4

        MaterialEditMenuButton {
            enabled: root.canEdit && root.hasSelection
            text: Translation.tr("Cut")
            onTriggered: {
                root.target?.cut();
                root.close();
            }
        }

        MaterialEditMenuButton {
            enabled: root.hasSelection
            text: Translation.tr("Copy")
            onTriggered: {
                root.target?.copy();
                root.close();
            }
        }

        MaterialEditMenuButton {
            enabled: root.canEdit
            text: Translation.tr("Paste")
            onTriggered: {
                root.target?.paste();
                root.close();
            }
        }

        MaterialEditMenuButton {
            enabled: root.hasText
            text: Translation.tr("Select all")
            onTriggered: {
                root.target?.selectAll();
                root.close();
            }
        }
    }

    component MaterialEditMenuButton: RippleButton {
        id: menuButton
        signal triggered()

        implicitWidth: 164
        implicitHeight: 34
        horizontalPadding: 12
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

        downAction: () => menuButton.triggered()

        contentItem: StyledText {
            anchors.fill: parent
            anchors.leftMargin: menuButton.horizontalPadding
            anchors.rightMargin: menuButton.horizontalPadding
            text: menuButton.text
            color: menuButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer2Disabled
            verticalAlignment: Text.AlignVCenter
        }
    }
}
