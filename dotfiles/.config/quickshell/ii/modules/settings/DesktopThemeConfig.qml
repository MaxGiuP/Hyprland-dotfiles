import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 860

    component OverviewCard: Rectangle {
        id: overviewCard
        required property string title
        required property string icon
        property string line1: ""
        property string line2: ""
        property string line3: ""

        Layout.fillWidth: true
        implicitHeight: 144
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: overviewCard.icon
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: overviewCard.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
            }

            StyledText {
                visible: text.length > 0
                text: overviewCard.line1
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.Wrap
            }
            StyledText {
                visible: text.length > 0
                text: overviewCard.line2
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
            StyledText {
                visible: text.length > 0
                text: overviewCard.line3
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }

    component LabeledField: ColumnLayout {
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

    component LabeledCombo: ColumnLayout {
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

    ContentSection {
        icon: "palette"
        title: Translation.tr("Desktop style hub")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Manage the theme stack that Quickshell sits on top of: GTK config files, GNOME interface settings, and KDE or Qt theme files from one place.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            OverviewCard {
                title: Translation.tr("GTK")
                icon: "palette"
                line1: `${Translation.tr("GTK3")}: ${DesktopThemeSettings.gtk3Theme || "-"}`
                line2: `${Translation.tr("GTK4")}: ${DesktopThemeSettings.gtk4Theme || "-"}`
                line3: `${Translation.tr("Icons")}: ${DesktopThemeSettings.gtk4IconTheme || DesktopThemeSettings.gtk3IconTheme || "-"}`
            }

            OverviewCard {
                title: Translation.tr("GNOME")
                icon: "deployed_code"
                line1: `${Translation.tr("Theme")}: ${DesktopThemeSettings.gnomeGtkTheme || "-"}`
                line2: `${Translation.tr("Color scheme")}: ${DesktopThemeSettings.gnomeColorScheme || "-"}`
                line3: `${Translation.tr("Font")}: ${DesktopThemeSettings.gnomeFont || "-"}`
            }

            OverviewCard {
                title: Translation.tr("KDE / Qt")
                icon: "widgets"
                line1: `${Translation.tr("Colors")}: ${DesktopThemeSettings.kdeColorScheme || "-"}`
                line2: `${Translation.tr("Look and feel")}: ${DesktopThemeSettings.kdeLookAndFeel || "-"}`
                line3: `${Translation.tr("Kvantum")}: ${DesktopThemeSettings.kvantumTheme || "-"}`
            }
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "edit_document"
                mainText: Translation.tr("GTK 3 file")
                onClicked: DesktopThemeSettings.openFile(DesktopThemeSettings.gtk3Path)
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "edit_document"
                mainText: Translation.tr("GTK 4 file")
                onClicked: DesktopThemeSettings.openFile(DesktopThemeSettings.gtk4Path)
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "edit_document"
                mainText: Translation.tr("kdeglobals")
                onClicked: DesktopThemeSettings.openFile(DesktopThemeSettings.kdeGlobalsPath)
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "refresh"
                mainText: Translation.tr("Refresh values")
                onClicked: DesktopThemeSettings.refreshAll()
            }
        }
    }

    ContentSection {
        icon: "wallpaper"
        title: Translation.tr("Personalisation")

        ConfigRow {
            uniform: true

            Repeater {
                model: [
                    { dark: false, icon: "light_mode", label: Translation.tr("Light mode") },
                    { dark: true, icon: "dark_mode", label: Translation.tr("Dark mode") }
                ]

                delegate: RippleButtonWithIcon {
                    required property var modelData
                    Layout.fillWidth: true
                    materialIcon: modelData.icon
                    mainText: modelData.label
                    toggled: Appearance.m3colors.darkmode === modelData.dark
                    onClicked: Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${modelData.dark ? "dark" : "light"} --noswitch`])
                }
            }
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "wallpaper"
                mainText: Translation.tr("Change wallpaper")
                onClicked: Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode)
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "bottom_app_bar"
                mainText: Translation.tr("Open shell interface files")
                onClicked: Qt.openUrlExternally(`file://${Directories.config}/illogical-impulse`)
            }
        }

        ContentSubsection {
            title: Translation.tr("Color palette style")

            ConfigSelectionArray {
                currentValue: Config.options.appearance.palette.type
                onSelected: newValue => {
                    Config.options.appearance.palette.type = newValue
                    Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --noswitch`])
                }
                options: [
                    { value: "auto", displayName: Translation.tr("Auto") },
                    { value: "scheme-content", displayName: Translation.tr("Content") },
                    { value: "scheme-expressive", displayName: Translation.tr("Expressive") },
                    { value: "scheme-fidelity", displayName: Translation.tr("Fidelity") },
                    { value: "scheme-fruit-salad", displayName: Translation.tr("Fruit Salad") },
                    { value: "scheme-monochrome", displayName: Translation.tr("Monochrome") },
                    { value: "scheme-neutral", displayName: Translation.tr("Neutral") },
                    { value: "scheme-rainbow", displayName: Translation.tr("Rainbow") },
                    { value: "scheme-tonal-spot", displayName: Translation.tr("Tonal Spot") }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "ev_shadow"
            text: Translation.tr("Transparency")
            checked: Config.options.appearance.transparency.enable
            onCheckedChanged: Config.options.appearance.transparency.enable = checked
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Shell appearance quick controls")

        ConfigRow {
            uniform: true

            ContentSubsection {
                title: Translation.tr("Bar position")

                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0
                        Config.options.bar.vertical = (newValue & 2) !== 0
                    }
                    options: [
                        { displayName: Translation.tr("Top"), icon: "arrow_upward", value: 0 },
                        { displayName: Translation.tr("Left"), icon: "arrow_back", value: 2 },
                        { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: 1 },
                        { displayName: Translation.tr("Right"), icon: "arrow_forward", value: 3 }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Bar style")

                ConfigSelectionArray {
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => {
                        Config.options.bar.cornerStyle = newValue
                    }
                    options: [
                        { displayName: Translation.tr("Hug"), icon: "line_curve", value: 0 },
                        { displayName: Translation.tr("Float"), icon: "page_header", value: 1 },
                        { displayName: Translation.tr("Rect"), icon: "toolbar", value: 2 }
                    ]
                }
            }
        }

        ConfigRow {
            uniform: true

            ContentSubsection {
                title: Translation.tr("Screen round corner")

                ConfigSelectionArray {
                    currentValue: Config.options.appearance.fakeScreenRounding
                    onSelected: newValue => {
                        Config.options.appearance.fakeScreenRounding = newValue
                    }
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                        { displayName: Translation.tr("When not fullscreen"), icon: "fullscreen_exit", value: 2 }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Bar transparency")

                ConfigSelectionArray {
                    currentValue: Config.options.bar.backgroundOpacity
                    onSelected: newValue => {
                        Config.options.bar.backgroundOpacity = newValue
                    }
                    options: [
                        { displayName: Translation.tr("Off"), icon: "rectangle", value: 0 },
                        { displayName: Translation.tr("Half"), icon: "opacity", value: 1 },
                        { displayName: Translation.tr("Full"), icon: "gradient", value: 2 }
                    ]
                }
            }
        }
    }

    ContentSection {
        icon: "app_registration"
        title: Translation.tr("GTK theme files")

        ContentSubsection {
            title: Translation.tr("GTK 3")

            ConfigRow {
                uniform: true
                LabeledCombo {
                    id: gtk3ThemeCombo
                    label: Translation.tr("Theme preset")
                    options: DesktopThemeSettings.gtkThemeOptions
                    currentValue: DesktopThemeSettings.gtk3Theme
                }
                LabeledCombo {
                    id: gtk3IconCombo
                    label: Translation.tr("Icon preset")
                    options: DesktopThemeSettings.iconThemeOptions
                    currentValue: DesktopThemeSettings.gtk3IconTheme
                }
            }

            ConfigRow {
                uniform: true
                LabeledCombo {
                    id: gtk3CursorCombo
                    label: Translation.tr("Cursor preset")
                    options: DesktopThemeSettings.cursorThemeOptions
                    currentValue: DesktopThemeSettings.gtk3CursorTheme
                }
                LabeledCombo {
                    id: gtk3FontFamilyCombo
                    label: Translation.tr("Font family")
                    options: DesktopThemeSettings.fontFamilyOptions
                    currentValue: DesktopThemeSettings.parseGtkFontFamily(DesktopThemeSettings.gtk3Font)
                }
            }

            RowLayout {
                id: gtk3Row
                Layout.fillWidth: true
                spacing: 10

                LabeledField {
                    id: gtk3CursorSizeField
                    Layout.preferredWidth: 180
                    label: Translation.tr("Cursor size")
                    text: `${DesktopThemeSettings.gtk3CursorSize}`
                }

                LabeledCombo {
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
                LabeledCombo {
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
                LabeledCombo {
                    id: gtk4ThemeCombo
                    label: Translation.tr("Theme preset")
                    options: DesktopThemeSettings.gtkThemeOptions
                    currentValue: DesktopThemeSettings.gtk4Theme
                }
                LabeledCombo {
                    id: gtk4IconCombo
                    label: Translation.tr("Icon preset")
                    options: DesktopThemeSettings.iconThemeOptions
                    currentValue: DesktopThemeSettings.gtk4IconTheme
                }
            }

            ConfigRow {
                uniform: true
                LabeledCombo {
                    id: gtk4CursorCombo
                    label: Translation.tr("Cursor preset")
                    options: DesktopThemeSettings.cursorThemeOptions
                    currentValue: DesktopThemeSettings.gtk4CursorTheme
                }
                LabeledCombo {
                    id: gtk4FontFamilyCombo
                    label: Translation.tr("Font family")
                    options: DesktopThemeSettings.fontFamilyOptions
                    currentValue: DesktopThemeSettings.parseGtkFontFamily(DesktopThemeSettings.gtk4Font)
                }
            }

            RowLayout {
                id: gtk4Row
                Layout.fillWidth: true
                spacing: 10

                LabeledField {
                    id: gtk4CursorSizeField
                    Layout.preferredWidth: 180
                    label: Translation.tr("Cursor size")
                    text: `${DesktopThemeSettings.gtk4CursorSize}`
                }

                LabeledCombo {
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
                LabeledCombo {
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
                        gnomeThemeCombo.combo.currentIndex = gtk4ThemeCombo.combo.currentIndex
                        gnomeIconCombo.combo.currentIndex = gtk4IconCombo.combo.currentIndex
                        gnomeCursorCombo.combo.currentIndex = gtk4CursorCombo.combo.currentIndex
                        gnomeFontFamilyCombo.combo.currentIndex = gtk4FontFamilyCombo.combo.currentIndex
                        gnomeFontSizeSpin.value = gtk4FontSizeSpin.value
                        gnomeFontSizePresetCombo.combo.currentIndex = gtk4FontSizePresetCombo.combo.currentIndex
                        gnomeWeightCombo.combo.currentIndex = gtk4WeightCombo.combo.currentIndex
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
                LabeledField {
                    label: Translation.tr("GTK 3 current theme")
                    text: DesktopThemeSettings.gtk3Theme
                }
                LabeledField {
                    label: Translation.tr("GTK 4 current theme")
                    text: DesktopThemeSettings.gtk4Theme
                }
            }
        }
    }

    ContentSection {
        icon: "deployed_code"
        title: Translation.tr("GNOME interface settings")

        ConfigRow {
            uniform: true
            LabeledCombo {
                id: gnomeThemeCombo
                label: Translation.tr("GTK theme")
                options: DesktopThemeSettings.gtkThemeOptions
                currentValue: DesktopThemeSettings.gnomeGtkTheme
            }
            LabeledCombo {
                id: gnomeIconCombo
                label: Translation.tr("Icon theme")
                options: DesktopThemeSettings.iconThemeOptions
                currentValue: DesktopThemeSettings.gnomeIconTheme
            }
        }

        ConfigRow {
            uniform: true
            LabeledCombo {
                id: gnomeCursorCombo
                label: Translation.tr("Cursor theme")
                options: DesktopThemeSettings.cursorThemeOptions
                currentValue: DesktopThemeSettings.gnomeCursorTheme
            }
            LabeledCombo {
                id: gnomeFontFamilyCombo
                label: Translation.tr("Font family")
                options: DesktopThemeSettings.fontFamilyOptions
                currentValue: DesktopThemeSettings.parseGtkFontFamily(DesktopThemeSettings.gnomeFont)
            }
        }

        StyledText {
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Color scheme")
        }

        StyledComboBox {
            id: gnomeColorCombo
            textRole: "displayName"
            model: [
                { displayName: Translation.tr("Default"), value: "default", icon: "contrast" },
                { displayName: Translation.tr("Prefer dark"), value: "prefer-dark", icon: "dark_mode" },
                { displayName: Translation.tr("Prefer light"), value: "prefer-light", icon: "light_mode" }
            ]
            currentIndex: Math.max(0, model.findIndex(item => item.value === DesktopThemeSettings.gnomeColorScheme))
        }

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                id: gnomeCursorSizeSpin
                icon: "mouse"
                text: Translation.tr("Cursor size")
                from: 16
                to: 96
                stepSize: 1
                value: DesktopThemeSettings.gnomeCursorSize
            }
            ConfigSpinBox {
                id: gnomeTextScalingSpin
                icon: "format_size"
                text: Translation.tr("Text scaling (%)")
                from: 50
                to: 200
                stepSize: 5
                value: Math.round(DesktopThemeSettings.gnomeTextScaling * 100)
            }
        }

        ConfigRow {
            uniform: true
            LabeledCombo {
                id: gnomeFontSizePresetCombo
                label: Translation.tr("Size preset")
                options: DesktopThemeSettings.fontSizeOptions
                currentValue: `${DesktopThemeSettings.parseGtkFontSize(DesktopThemeSettings.gnomeFont)}`
                onValuePicked: value => gnomeFontSizeSpin.value = Number(value || gnomeFontSizeSpin.value)
            }
            ConfigSpinBox {
                id: gnomeFontSizeSpin
                icon: "text_fields"
                text: Translation.tr("Font size")
                from: 8
                to: 24
                stepSize: 1
                value: DesktopThemeSettings.parseGtkFontSize(DesktopThemeSettings.gnomeFont)
            }
            LabeledCombo {
                id: gnomeWeightCombo
                label: Translation.tr("Weight")
                options: DesktopThemeSettings.fontWeightOptions
                currentValue: DesktopThemeSettings.parseGtkFontWeight(DesktopThemeSettings.gnomeFont)
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                id: gnomeAnimationsSwitch
                buttonIcon: "animation"
                text: Translation.tr("Animations")
                checked: DesktopThemeSettings.gnomeAnimations
            }
            ConfigSwitch {
                id: gnomeHotCornersSwitch
                buttonIcon: "crop_free"
                text: Translation.tr("Hot corners")
                checked: DesktopThemeSettings.gnomeHotCorners
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                id: gnomeBatteryPercentSwitch
                buttonIcon: "battery_full_alt"
                text: Translation.tr("Show battery percentage")
                checked: DesktopThemeSettings.gnomeShowBatteryPercentage
            }
            StyledComboBox {
                id: gnomeClockCombo
                textRole: "displayName"
                model: [
                    { displayName: Translation.tr("24-hour"), value: "24h", icon: "schedule" },
                    { displayName: Translation.tr("12-hour"), value: "12h", icon: "schedule" }
                ]
                currentIndex: Math.max(0, model.findIndex(item => item.value === DesktopThemeSettings.gnomeClockFormat))
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "settings"
            mainText: Translation.tr("Apply GNOME interface settings")
            onClicked: DesktopThemeSettings.applyGnome({
                gtkTheme: gnomeThemeCombo.combo.model[gnomeThemeCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.gnomeGtkTheme,
                iconTheme: gnomeIconCombo.combo.model[gnomeIconCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.gnomeIconTheme,
                cursorTheme: gnomeCursorCombo.combo.model[gnomeCursorCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.gnomeCursorTheme,
                fontFamily: gnomeFontFamilyCombo.combo.model[gnomeFontFamilyCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.parseGtkFontFamily(DesktopThemeSettings.gnomeFont),
                fontWeight: gnomeWeightCombo.combo.model[gnomeWeightCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.parseGtkFontWeight(DesktopThemeSettings.gnomeFont),
                fontSize: gnomeFontSizeSpin.value,
                colorScheme: gnomeColorCombo.model[gnomeColorCombo.currentIndex]?.value ?? "default",
                cursorSize: gnomeCursorSizeSpin.value,
                textScaling: gnomeTextScalingSpin.value / 100,
                animations: gnomeAnimationsSwitch.checked,
                hotCorners: gnomeHotCornersSwitch.checked,
                showBatteryPercentage: gnomeBatteryPercentSwitch.checked,
                clockFormat: gnomeClockCombo.model[gnomeClockCombo.currentIndex]?.value ?? "24h"
            })
        }
    }

    ContentSection {
        icon: "widgets"
        title: Translation.tr("KDE / Qt theme files")

        ConfigRow {
            uniform: true
            LabeledCombo {
                id: kdeColorCombo
                label: Translation.tr("Color scheme")
                options: DesktopThemeSettings.kdeColorSchemeOptions
                currentValue: DesktopThemeSettings.kdeColorScheme
            }
            LabeledCombo {
                id: kdeIconCombo
                label: Translation.tr("Icon theme")
                options: DesktopThemeSettings.iconThemeOptions
                currentValue: DesktopThemeSettings.kdeIconTheme
            }
        }

        ConfigRow {
            uniform: true
            LabeledCombo {
                id: kdeLookCombo
                label: Translation.tr("Look and feel package")
                options: DesktopThemeSettings.kdeLookAndFeelOptions
                currentValue: DesktopThemeSettings.kdeLookAndFeel
            }
            LabeledCombo {
                id: kdeFontFamilyCombo
                label: Translation.tr("Font family")
                options: DesktopThemeSettings.fontFamilyOptions
                currentValue: DesktopThemeSettings.parseKdeFontFamily(DesktopThemeSettings.kdeFont)
            }
        }

        ConfigRow {
            uniform: true
            LabeledCombo {
                id: kvantumCombo
                label: Translation.tr("Kvantum theme")
                options: DesktopThemeSettings.kvantumThemeOptions
                currentValue: DesktopThemeSettings.kvantumTheme
            }
            ConfigSwitch {
                id: kdeAutoLookSwitch
                buttonIcon: "auto_mode"
                text: Translation.tr("Automatic look and feel")
                checked: DesktopThemeSettings.kdeAutomaticLookAndFeel
            }
        }

        ConfigSwitch {
            id: kdeDeleteSwitch
            buttonIcon: "delete"
            text: Translation.tr("Show Delete command")
            checked: DesktopThemeSettings.kdeShowDeleteCommand
        }

        ConfigRow {
            uniform: true
            LabeledCombo {
                id: kdeFontSizePresetCombo
                label: Translation.tr("Size preset")
                options: DesktopThemeSettings.fontSizeOptions
                currentValue: `${DesktopThemeSettings.parseKdeFontSize(DesktopThemeSettings.kdeFont)}`
                onValuePicked: value => kdeFontSizeSpin.value = Number(value || kdeFontSizeSpin.value)
            }
            ConfigSpinBox {
                id: kdeFontSizeSpin
                icon: "format_size"
                text: Translation.tr("Font size")
                from: 8
                to: 24
                stepSize: 1
                value: DesktopThemeSettings.parseKdeFontSize(DesktopThemeSettings.kdeFont)
            }
            LabeledCombo {
                id: kdeWeightCombo
                label: Translation.tr("Weight")
                options: DesktopThemeSettings.fontWeightOptions
                currentValue: DesktopThemeSettings.parseKdeFontWeight(DesktopThemeSettings.kdeFont)
            }
        }

        ConfigRow {
            uniform: true
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "save"
                mainText: Translation.tr("Save kdeglobals")
                onClicked: DesktopThemeSettings.saveKde({
                    colorScheme: kdeColorCombo.combo.model[kdeColorCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.kdeColorScheme,
                    iconTheme: kdeIconCombo.combo.model[kdeIconCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.kdeIconTheme,
                    lookAndFeel: kdeLookCombo.combo.model[kdeLookCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.kdeLookAndFeel,
                    fontFamily: kdeFontFamilyCombo.combo.model[kdeFontFamilyCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.parseKdeFontFamily(DesktopThemeSettings.kdeFont),
                    fontWeight: kdeWeightCombo.combo.model[kdeWeightCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.parseKdeFontWeight(DesktopThemeSettings.kdeFont),
                    fontSize: kdeFontSizeSpin.value
                })
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "save"
                mainText: Translation.tr("Save Kvantum theme")
                onClicked: DesktopThemeSettings.saveKvantumTheme(kvantumCombo.combo.model[kvantumCombo.combo.currentIndex]?.value ?? DesktopThemeSettings.kvantumTheme)
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "tune"
            mainText: Translation.tr("Save KDE behavior toggles")
            onClicked: DesktopThemeSettings.saveKdeToggles({
                automaticLookAndFeel: kdeAutoLookSwitch.checked,
                showDeleteCommand: kdeDeleteSwitch.checked
            })
        }
    }

    ContentSection {
        icon: "storefront"
        title: Translation.tr("KDE Store")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Open KDE's KNewStuff catalogs directly from here to download new global themes, icons, cursors, color schemes, GTK themes, and window decorations.")
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: DesktopThemeSettings.kdeStoreOptions

                delegate: RippleButtonWithIcon {
                    required property var modelData
                    materialIcon: "download"
                    mainText: modelData.displayName
                    mainContentComponent: Component {
                        ColumnLayout {
                            spacing: 1

                            StyledText {
                                text: modelData.displayName
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSecondaryContainer
                            }

                            StyledText {
                                text: modelData.description
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSecondaryContainer
                                opacity: 0.75
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                    onClicked: DesktopThemeSettings.openKdeStore(modelData.knsrc)
                }
            }
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "settings_applications"
                mainText: Translation.tr("Open KDE System Settings")
                onClicked: DesktopThemeSettings.openSystemSettings()
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "edit_document"
                mainText: Translation.tr("Open kdeglobals")
                onClicked: DesktopThemeSettings.openFile(DesktopThemeSettings.kdeGlobalsPath)
            }
        }
    }
}
