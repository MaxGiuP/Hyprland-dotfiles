import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentSection {
    id: gtkSection
    property var settingsHost: null

    component DesktopThemeCursorPreview: Item {
        id: cursorPreviewItem
        required property string themeName
        property string svgPath: ""
        implicitWidth: 64
        implicitHeight: 64

        onThemeNameChanged: {
            svgPath = ""
            if (themeName.length > 0) extractProc.running = true
        }

        Process {
            id: extractProc
            running: false
            command: ["bash", "-c",
                `theme="$1"
                 for dir in "$HOME/.icons" "/usr/share/icons"; do
                   f="$dir/$theme/hyprcursors/left_ptr.hlc"
                   [ -f "$f" ] || continue
                   preview_dir="\${XDG_RUNTIME_DIR:-/tmp}"
                   out=$(mktemp "$preview_dir/qs-cursor-preview.XXXXXX.svg") || exit 1
                   unzip -p "$f" "*.svg" 2>/dev/null | head -c 65536 > "$out"
                   if [ -s "$out" ]; then echo "$out"; else rm -f "$out"; fi
                   exit 0
                 done`,
                "ii-cursor-preview",
                cursorPreviewItem.themeName
            ]
            stdout: SplitParser {
                onRead: data => cursorPreviewItem.svgPath = data.trim()
            }
        }

        Image {
            anchors.fill: parent
            visible: cursorPreviewItem.svgPath.length > 0
            source: cursorPreviewItem.svgPath
            sourceSize.width: 64
            sourceSize.height: 64
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        MaterialSymbol {
            visible: cursorPreviewItem.svgPath.length === 0
            anchors.centerIn: parent
            text: "mouse"
            iconSize: 40
            color: Appearance.colors.colOnLayer1
            opacity: 0.35
        }
    }



    component DesktopThemeIconPreview: Item {
        id: iconPreviewItem
        required property string themeName
        property var iconPaths: []
        implicitHeight: 52
        Layout.fillWidth: true

        onThemeNameChanged: {
            iconPaths = []
            if (themeName.length > 0) findIconsProc.running = true
        }

        Process {
            id: findIconsProc
            running: false
            command: ["bash", "-c",
                `theme="$1"
                 icons="folder text-x-generic image-x-generic audio-x-generic application-x-executable"
                 for icon in $icons; do
                   result=""
                   for dir in "$HOME/.icons" "/usr/share/icons"; do
                     td="$dir/$theme"
                     [ -d "$td" ] || continue
                     f=$(find "$td" -name "$icon.svg" -o -name "$icon.png" 2>/dev/null | sort -t '/' -k 5 -rn | head -1)
                     [ -n "$f" ] && result="$f" && break
                   done
                   if [ -n "$result" ]; then echo "$result"; else echo "none"; fi
                 done`,
                "ii-icon-preview",
                iconPreviewItem.themeName
            ]
            stdout: SplitParser {
                onRead: data => {
                    if (data.trim() !== "none")
                        iconPreviewItem.iconPaths = [...iconPreviewItem.iconPaths, data.trim()]
                }
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Repeater {
                model: iconPreviewItem.iconPaths

                delegate: Image {
                    required property string modelData
                    width: 40; height: 40
                    source: modelData
                    sourceSize.width: 40
                    sourceSize.height: 40
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }

            // Placeholder dots while loading
            Repeater {
                model: Math.max(0, 5 - iconPreviewItem.iconPaths.length)
                delegate: Rectangle {
                    width: 40; height: 40
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2
                    opacity: 0.5
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: ["folder", "description", "image", "music_note", "terminal"][index] ?? "apps"
                        iconSize: 22
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }


    component DesktopThemeLabeledField: ColumnLayout {
        required property string label
        property alias text: field.text
        property alias placeholderText: field.placeholderText
        Layout.fillWidth: true
        spacing: 4

        StyledText {
            text: parent.label
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        MaterialTextField {
            id: field
            Layout.fillWidth: true
        }
    }


    component DesktopThemeLabeledCombo: ColumnLayout {
        required property string label
        required property var options
        required property string currentValue
        property alias combo: combo
        property var onValuePicked: null
        Layout.fillWidth: true
        spacing: 4

        StyledText {
            text: parent.label
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledComboBox {
            id: combo
            Layout.fillWidth: true
            textRole: "displayName"
            model: parent.options
            currentIndex: Math.max(0, model.findIndex(item => item.value === parent.currentValue))
            onActivated: index => {
                if (parent.onValuePicked)
                    parent.onValuePicked(model[index]?.value)
            }
        }
    }


        icon: "app_registration"
        title: Translation.tr("GTK theme files")

        ContentSubsection {
title: Translation.tr("GTK 3")

ConfigRow {
    uniform: true
    DesktopThemeLabeledCombo {
        id: gtk3ThemeCombo
        label: Translation.tr("Theme preset")
        options: DesktopThemeSettings.gtkThemeOptions
        currentValue: DesktopThemeSettings.gtk3Theme
    }
    DesktopThemeLabeledCombo {
        id: gtk3IconCombo
        label: Translation.tr("Icon preset")
        options: DesktopThemeSettings.iconThemeOptions
        currentValue: DesktopThemeSettings.gtk3IconTheme
    }
}

ConfigRow {
    uniform: true
    DesktopThemeLabeledCombo {
        id: gtk3CursorCombo
        label: Translation.tr("Cursor preset")
        options: DesktopThemeSettings.cursorThemeOptions
        currentValue: DesktopThemeSettings.gtk3CursorTheme
    }
    DesktopThemeLabeledCombo {
        id: gtk3FontFamilyCombo
        label: Translation.tr("Font family")
        options: DesktopThemeSettings.fontFamilyOptions
        currentValue: DesktopThemeSettings.parseGtkFontFamily(DesktopThemeSettings.gtk3Font)
    }
}

// ── Live cursor + icon previews for GTK 3 ─────────────────────
RowLayout {
    Layout.fillWidth: true
    spacing: 12

    // Cursor preview
    Rectangle {
        implicitWidth: 88; implicitHeight: 72
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4
            DesktopThemeCursorPreview {
                Layout.alignment: Qt.AlignHCenter
                themeName: gtk3CursorCombo.combo.model[gtk3CursorCombo.combo.currentIndex]?.value ?? ""
                implicitWidth: 44; implicitHeight: 44
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Cursor")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    // Icon theme preview
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        StyledText {
            text: Translation.tr("Icons: %1").arg(gtk3IconCombo.combo.model[gtk3IconCombo.combo.currentIndex]?.value ?? "—")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        DesktopThemeIconPreview {
            themeName: gtk3IconCombo.combo.model[gtk3IconCombo.combo.currentIndex]?.value ?? ""
            Layout.fillWidth: true
        }
    }
}

RowLayout {
    id: gtk3Row
    Layout.fillWidth: true
    spacing: 10

    DesktopThemeLabeledField {
        id: gtk3CursorSizeField
        Layout.preferredWidth: 180
        label: Translation.tr("Cursor size")
        text: `${DesktopThemeSettings.gtk3CursorSize}`
    }

    DesktopThemeLabeledCombo {
        id: gtk3FontSizePresetCombo
        label: Translation.tr("Size preset")
        options: DesktopThemeSettings.fontSizeOptions
        currentValue: `${DesktopThemeSettings.parseGtkFontSize(DesktopThemeSettings.gtk3Font)}`
        onValuePicked: value => gtk3FontSizeSpin.value = Number(value || gtk3FontSizeSpin.value)
    }

    ConfigSpinBox {
        id: gtk3FontSizeSpin
        icon: "format_size"
        text: Translation.tr("Font size")
        from: 8
        to: 24
        stepSize: 1
        value: DesktopThemeSettings.parseGtkFontSize(DesktopThemeSettings.gtk3Font)
    }
}

ConfigRow {
    uniform: true
    DesktopThemeLabeledCombo {
        id: gtk3WeightCombo
        label: Translation.tr("Weight")
        options: DesktopThemeSettings.fontWeightOptions
        currentValue: DesktopThemeSettings.parseGtkFontWeight(DesktopThemeSettings.gtk3Font)
    }
    ConfigSwitch {
        id: gtk3DarkSwitch
        buttonIcon: "dark_mode"
        text: Translation.tr("Prefer dark GTK apps")
        checked: DesktopThemeSettings.gtk3PreferDark
    }
}

RippleButtonWithIcon {
    Layout.fillWidth: true
    materialIcon: "save"
    mainText: Translation.tr("Save GTK 3 settings.ini")
    onClicked: DesktopThemeSettings.saveGtk3({
        theme: gtk3ThemeCombo.combo.model[gtk3ThemeCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.gtk3Theme,
        iconTheme: gtk3IconCombo.combo.model[gtk3IconCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.gtk3IconTheme,
        cursorTheme: gtk3CursorCombo.combo.model[gtk3CursorCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.gtk3CursorTheme,
        fontFamily: gtk3FontFamilyCombo.combo.model[gtk3FontFamilyCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.parseGtkFontFamily(DesktopThemeSettings.gtk3Font),
        fontWeight: gtk3WeightCombo.combo.model[gtk3WeightCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.parseGtkFontWeight(DesktopThemeSettings.gtk3Font),
        fontSize: gtk3FontSizeSpin.value,
        cursorSize: Number(gtk3CursorSizeField.text.trim() || "24"),
        preferDark: gtk3DarkSwitch.checked
    })
}
        }

        ContentSubsection {
title: Translation.tr("GTK 4")

ConfigRow {
    uniform: true
    DesktopThemeLabeledCombo {
        id: gtk4ThemeCombo
        label: Translation.tr("Theme preset")
        options: DesktopThemeSettings.gtkThemeOptions
        currentValue: DesktopThemeSettings.gtk4Theme
    }
    DesktopThemeLabeledCombo {
        id: gtk4IconCombo
        label: Translation.tr("Icon preset")
        options: DesktopThemeSettings.iconThemeOptions
        currentValue: DesktopThemeSettings.gtk4IconTheme
    }
}

ConfigRow {
    uniform: true
    DesktopThemeLabeledCombo {
        id: gtk4CursorCombo
        label: Translation.tr("Cursor preset")
        options: DesktopThemeSettings.cursorThemeOptions
        currentValue: DesktopThemeSettings.gtk4CursorTheme
    }
    DesktopThemeLabeledCombo {
        id: gtk4FontFamilyCombo
        label: Translation.tr("Font family")
        options: DesktopThemeSettings.fontFamilyOptions
        currentValue: DesktopThemeSettings.parseGtkFontFamily(DesktopThemeSettings.gtk4Font)
    }
}

// ── Live cursor + icon previews for GTK 4 ─────────────────────
RowLayout {
    Layout.fillWidth: true
    spacing: 12

    Rectangle {
        implicitWidth: 88; implicitHeight: 72
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4
            DesktopThemeCursorPreview {
                Layout.alignment: Qt.AlignHCenter
                themeName: gtk4CursorCombo.combo.model[gtk4CursorCombo.combo.currentIndex]?.value ?? ""
                implicitWidth: 44; implicitHeight: 44
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Cursor")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        StyledText {
            text: Translation.tr("Icons: %1").arg(gtk4IconCombo.combo.model[gtk4IconCombo.combo.currentIndex]?.value ?? "—")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        DesktopThemeIconPreview {
            themeName: gtk4IconCombo.combo.model[gtk4IconCombo.combo.currentIndex]?.value ?? ""
            Layout.fillWidth: true
        }
    }
}

RowLayout {
    id: gtk4Row
    Layout.fillWidth: true
    spacing: 10

    DesktopThemeLabeledField {
        id: gtk4CursorSizeField
        Layout.preferredWidth: 180
        label: Translation.tr("Cursor size")
        text: `${DesktopThemeSettings.gtk4CursorSize}`
    }

    DesktopThemeLabeledCombo {
        id: gtk4FontSizePresetCombo
        label: Translation.tr("Size preset")
        options: DesktopThemeSettings.fontSizeOptions
        currentValue: `${DesktopThemeSettings.parseGtkFontSize(DesktopThemeSettings.gtk4Font)}`
        onValuePicked: value => gtk4FontSizeSpin.value = Number(value || gtk4FontSizeSpin.value)
    }

    ConfigSpinBox {
        id: gtk4FontSizeSpin
        icon: "format_size"
        text: Translation.tr("Font size")
        from: 8
        to: 24
        stepSize: 1
        value: DesktopThemeSettings.parseGtkFontSize(DesktopThemeSettings.gtk4Font)
    }
}

ConfigRow {
    uniform: true
    DesktopThemeLabeledCombo {
        id: gtk4WeightCombo
        label: Translation.tr("Weight")
        options: DesktopThemeSettings.fontWeightOptions
        currentValue: DesktopThemeSettings.parseGtkFontWeight(DesktopThemeSettings.gtk4Font)
    }
    ConfigSwitch {
        id: gtk4DarkSwitch
        buttonIcon: "dark_mode"
        text: Translation.tr("Prefer dark GTK apps")
        checked: DesktopThemeSettings.gtk4PreferDark
    }
}

ConfigRow {
    uniform: true
    RippleButtonWithIcon {
        Layout.fillWidth: true
        materialIcon: "save"
        mainText: Translation.tr("Save GTK 4 settings.ini")
        onClicked: DesktopThemeSettings.saveGtk4({
            theme: gtk4ThemeCombo.combo.model[gtk4ThemeCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.gtk4Theme,
            iconTheme: gtk4IconCombo.combo.model[gtk4IconCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.gtk4IconTheme,
            cursorTheme: gtk4CursorCombo.combo.model[gtk4CursorCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.gtk4CursorTheme,
            fontFamily: gtk4FontFamilyCombo.combo.model[gtk4FontFamilyCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.parseGtkFontFamily(DesktopThemeSettings.gtk4Font),
            fontWeight: gtk4WeightCombo.combo.model[gtk4WeightCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.parseGtkFontWeight(DesktopThemeSettings.gtk4Font),
            fontSize: gtk4FontSizeSpin.value,
            cursorSize: Number(gtk4CursorSizeField.text.trim() || "24"),
            preferDark: gtk4DarkSwitch.checked
        })
    }

    RippleButtonWithIcon {
        Layout.fillWidth: true
        materialIcon: "content_copy"
        mainText: Translation.tr("Copy GTK 4 values into GNOME")
        onClicked: {
            if (gtkSection.settingsHost)
                gtkSection.settingsHost.copyGtk4DraftToGnome({
                    themeIndex: gtk4ThemeCombo.combo.currentIndex,
                    iconIndex: gtk4IconCombo.combo.currentIndex,
                    cursorIndex: gtk4CursorCombo.combo.currentIndex,
                    fontFamilyIndex: gtk4FontFamilyCombo.combo.currentIndex,
                    fontSize: gtk4FontSizeSpin.value,
                    fontSizePresetIndex: gtk4FontSizePresetCombo.combo.currentIndex,
                    weightIndex: gtk4WeightCombo.combo.currentIndex
                })
        }
    }
}
        }

        ContentSubsection {
title: Translation.tr("Advanced GTK values")

StyledText {
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    color: Appearance.colors.colSubtext
    text: Translation.tr("Preset lists handle the common cases. Keep the exact font strings here, and use file shortcuts above when you need to hand-edit edge cases.")
}

ConfigRow {
    uniform: true
    DesktopThemeLabeledField {
        label: Translation.tr("GTK 3 current theme")
        text: DesktopThemeSettings.gtk3Theme
    }
    DesktopThemeLabeledField {
        label: Translation.tr("GTK 4 current theme")
        text: DesktopThemeSettings.gtk4Theme
    }
}
        }
}
