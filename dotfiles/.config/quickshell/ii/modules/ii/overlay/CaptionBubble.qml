import QtQuick
import qs.modules.common

// Caption surfaces need enough opacity to stay readable over arbitrary content.
// Bind to the same palette as the shell so theme changes apply while pinned.
Rectangle {
    readonly property color foreground: Appearance.colors.colOnSurface
    readonly property color secondaryForeground: Appearance.highContrast
        ? foreground : Appearance.colors.colOnSurfaceVariant
    readonly property color translationForeground: Appearance.highContrast
        ? foreground : Appearance.colors.colPrimary
    readonly property color surface: Appearance.colors.colLayer1Base

    color: Qt.rgba(surface.r, surface.g, surface.b,
        Appearance.reduceTransparency || Appearance.highContrast ? 1 : 0.94)
    border.width: 1
    border.color: Appearance.highContrast
        ? Appearance.m3colors.m3outline : Appearance.colors.colOutlineVariant
    clip: true
}
