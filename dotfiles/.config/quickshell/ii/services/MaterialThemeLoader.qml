pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath

    function darken(color, amount) {
        return ColorUtils.mix(color, "#000000", 1 - amount)
    }

    function strengthenLightPalette() {
        // Material's generated light schemes are deliberately soft. Keep the
        // wallpaper hue, but give text, dividers and accents more definition.
        Appearance.m3colors.m3onBackground = root.darken(Appearance.m3colors.m3onBackground, 0.18)
        Appearance.m3colors.m3onSurface = root.darken(Appearance.m3colors.m3onSurface, 0.18)
        Appearance.m3colors.m3onSurfaceVariant = root.darken(Appearance.m3colors.m3onSurfaceVariant, 0.14)
        Appearance.m3colors.m3outline = root.darken(Appearance.m3colors.m3outline, 0.16)
        Appearance.m3colors.m3outlineVariant = root.darken(Appearance.m3colors.m3outlineVariant, 0.10)
        Appearance.m3colors.m3primary = root.darken(Appearance.m3colors.m3primary, 0.08)
        Appearance.m3colors.m3secondary = root.darken(Appearance.m3colors.m3secondary, 0.08)
        Appearance.m3colors.m3tertiary = root.darken(Appearance.m3colors.m3tertiary, 0.08)
    }

    function reapplyTheme() {
        themeFileView.reload()
    }

    function applyColors(fileContent) {
        const json = JSON.parse(fileContent)
        for (const key in json) {
            if (!json.hasOwnProperty(key))
                continue

            if (key === "darkmode") {
                Appearance.m3colors.darkmode = !!json[key]
                continue
            }

            // Convert snake_case to CamelCase
            const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
            const m3Key = `m3${camelCaseKey}`
            Appearance.m3colors[m3Key] = json[key]
        }

        // If the generator did not include an explicit mode, fall back to the
        // background luminance. Explicit mode is required because very dark
        // wallpapers can still be used with a deliberately light system theme.
        if (json.darkmode === undefined)
            Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)

        if (!Appearance.m3colors.darkmode)
            root.strengthenLightPalette()

        // Some downstream widgets use raw m3on* colors instead of Appearance.colors
        // wrappers. Normalize them to WCAG contrast against their actual current
        // backgrounds so light accents get dark text and dark accents get light text.
        Appearance.m3colors.m3onPrimary = ColorUtils.bestTextColor(Appearance.m3colors.m3primary)
        Appearance.m3colors.m3onPrimaryContainer = ColorUtils.bestTextColor(Appearance.m3colors.m3primaryContainer)
        Appearance.m3colors.m3onSecondary = ColorUtils.bestTextColor(Appearance.m3colors.m3secondary)
        Appearance.m3colors.m3onSecondaryContainer = ColorUtils.bestTextColor(Appearance.m3colors.m3secondaryContainer)
        Appearance.m3colors.m3onTertiary = ColorUtils.bestTextColor(Appearance.m3colors.m3tertiary)
        Appearance.m3colors.m3onTertiaryContainer = ColorUtils.bestTextColor(Appearance.m3colors.m3tertiaryContainer)
        Appearance.m3colors.m3onError = ColorUtils.bestTextColor(Appearance.m3colors.m3error)
        Appearance.m3colors.m3onErrorContainer = ColorUtils.bestTextColor(Appearance.m3colors.m3errorContainer)
    }

    function resetFilePathNextTime() {
        resetFilePathNextWallpaperChange.enabled = true
    }

    Connections {
        id: resetFilePathNextWallpaperChange
        enabled: false
        target: Config.options.background
        function onWallpaperPathChanged() {
            root.filePath = ""
            root.filePath = Directories.generatedMaterialThemePath
            resetFilePathNextWallpaperChange.enabled = false
        }
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
        repeat: false
        running: false
        onTriggered: {
            root.applyColors(themeFileView.text())
        }
    }

	FileView { 
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            this.reload()
            delayedFileRead.start()
        }
        onLoadedChanged: {
            const fileContent = themeFileView.text()
            root.applyColors(fileContent)
        }
        onLoadFailed: root.resetFilePathNextTime();
    }
}
