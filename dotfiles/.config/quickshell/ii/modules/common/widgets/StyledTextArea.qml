import qs.modules.common
import QtQuick
import QtQuick.Controls

/**
 * Does not include visual layout, but includes the easily neglected colors.
 */
TextArea {
    id: root
    renderType: Text.NativeRendering
    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    placeholderTextColor: Appearance.m3colors.m3outline
    color: Appearance.colors.colOnLayer0
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.disableVariableFonts ? ({}) : Appearance.font.variableAxes.main
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: eventPoint => editContextMenu.openAt(root, eventPoint.position.x, eventPoint.position.y)
    }

    MaterialEditContextMenu {
        id: editContextMenu
        target: root
    }
}
