import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 860

    // ── Cursor preview: extracts the left_ptr SVG from the .hlc zip ──────
    component CursorThemePreview: Item {
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
                `theme="${cursorPreviewItem.themeName}"
                 for dir in "$HOME/.icons" "/usr/share/icons"; do
                   f="$dir/$theme/hyprcursors/left_ptr.hlc"
                   [ -f "$f" ] || continue
                   out="/tmp/qs-cursor-preview-${theme}.svg"
                   unzip -p "$f" "*.svg" 2>/dev/null | head -c 65536 > "$out" && echo "$out"
                   exit 0
                 done`
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

    // ── Icon theme preview: finds icons directly from theme dir ───────────
    component IconThemePreview: Item {
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
                `theme="${iconPreviewItem.themeName}"
                 icons="folder text-x-generic image-x-generic audio-x-generic application-x-executable"
                 for icon in $icons; do
                   result=""
                   for dir in "$HOME/.icons" "/usr/share/icons"; do
                     td="$dir/$theme"
                     [ -d "$td" ] || continue
                     f=$(find "$td" -name "${icon}.svg" -o -name "${icon}.png" 2>/dev/null | sort -t '/' -k 5 -rn | head -1)
                     [ -n "$f" ] && result="$f" && break
                   done
                   echo "${result:-none}"
                 done`
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

        // ── Wallpaper live preview ─────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 200
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            clip: true

            Image {
                id: wallpaperPreviewImg
                anchors.fill: parent
                source: Config.options.background?.wallpaperPath ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            // Dim + info overlay
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 56
                color: Qt.rgba(0, 0, 0, 0.45)

                RowLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 10

                    MaterialSymbol {
                        text: "image"
                        iconSize: 20
                        color: "white"
                        opacity: 0.8
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const p = Config.options.background?.wallpaperPath ?? ""
                            return p.length > 0 ? p.split("/").pop() : Translation.tr("No wallpaper set")
                        }
                        color: "white"
                        font.pixelSize: Appearance.font.pixelSize.small
                        elide: Text.ElideLeft
                    }

                    RippleButton {
                        buttonRadius: Appearance.rounding.full
                        implicitWidth: 36; implicitHeight: 36
                        onClicked: Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode)
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "edit"
                            iconSize: 18
                            color: "white"
                        }
                        StyledToolTip { text: Translation.tr("Change wallpaper") }
                    }
                }
            }

            // Placeholder when no wallpaper
            ColumnLayout {
                visible: wallpaperPreviewImg.status !== Image.Ready
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "wallpaper"
                    iconSize: 48
                    color: Appearance.colors.colSubtext
                    opacity: 0.5
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Wallpaper preview")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }

        // ── Material You color palette ─────────────────────────────────────
        ContentSubsection {
            title: Translation.tr("Current color palette")

            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    model: [
                        { label: Translation.tr("Primary"),   color: Appearance.m3colors.m3primary },
                        { label: Translation.tr("Secondary"), color: Appearance.m3colors.m3secondary },
                        { label: Translation.tr("Tertiary"),  color: Appearance.m3colors.m3tertiary },
                        { label: Translation.tr("Error"),     color: Appearance.m3colors.m3error },
                        { label: Translation.tr("Surface"),   color: Appearance.m3colors.m3surfaceVariant },
                        { label: Translation.tr("Container"), color: Appearance.m3colors.m3primaryContainer },
                        { label: Translation.tr("On Pri."),   color: Appearance.m3colors.m3onPrimary },
                        { label: Translation.tr("On Sec."),   color: Appearance.m3colors.m3onSecondary },
                    ]

                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 36; height: 36
                            radius: Appearance.rounding.full
                            color: modelData.color
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.15)

                            StyledToolTip { text: modelData.label }
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }

        // ── Cursor theme preview ───────────────────────────────────────────
        ContentSubsection {
            title: Translation.tr("Cursor preview")

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                // Preview box for current applied cursor
                Rectangle {
                    implicitWidth: 100; implicitHeight: 80
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        CursorThemePreview {
                            id: appliedCursorPreview
                            Layout.alignment: Qt.AlignHCenter
                            themeName: DesktopThemeSettings.gtk3CursorTheme
                            implicitWidth: 48; implicitHeight: 48
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Applied")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: DesktopThemeSettings.gtk3CursorTheme || Translation.tr("None")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        text: Translation.tr("Size: %1px").arg(DesktopThemeSettings.gtk3CursorSize)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: Translation.tr("Change cursor theme in GTK 3 or GTK 4 sections below")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // ── Icon theme preview (current applied) ───────────────────────────
        ContentSubsection {
            title: Translation.tr("Icon theme preview")

            IconThemePreview {
                id: appliedIconPreview
                themeName: DesktopThemeSettings.gtk3IconTheme
                Layout.fillWidth: true
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Applied icon theme: %1").arg(DesktopThemeSettings.gtk3IconTheme || Translation.tr("system default"))
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }

        // ── Light / dark mode toggle ───────────────────────────────────────
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

        // ── Wallpaper folder thumbnails ────────────────────────────────────
        ContentSubsection {
            title: Translation.tr("Wallpaper folder")

            Component.onCompleted: Wallpapers.load()

            StyledFlickable {
                Layout.fillWidth: true
                implicitHeight: 108
                contentWidth: wallpaperRow.implicitWidth
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                clip: true

                Row {
                    id: wallpaperRow
                    spacing: 6

                    Repeater {
                        model: Wallpapers.wallpapers.slice(0, 20)

                        delegate: Rectangle {
                            required property string modelData
                            width: 160; height: 100
                            radius: Appearance.rounding.small
                            clip: true
                            color: Appearance.colors.colLayer2
                            border.width: modelData === (Config.options.background?.wallpaperPath ?? "") ? 2 : 0
                            border.color: Appearance.colors.colPrimary

                            ThumbnailImage {
                                anchors.fill: parent
                                sourcePath: modelData
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 160
                                sourceSize.height: 100
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Wallpapers.apply(modelData)
                            }

                            // Active indicator badge
                            Rectangle {
                                visible: modelData === (Config.options.background?.wallpaperPath ?? "")
                                anchors { top: parent.top; right: parent.right; margins: 6 }
                                width: 20; height: 20
                                radius: width / 2
                                color: Appearance.colors.colPrimary
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "check"
                                    iconSize: 13
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }

                    // "Browse more" tile
                    Rectangle {
                        width: 80; height: 100
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        border.width: 1
                        border.color: Appearance.colors.colOutlineVariant

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: "folder_open"
                                iconSize: 28
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("Browse")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode)
                        }
                    }
                }
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
                        CursorThemePreview {
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
                    IconThemePreview {
                        themeName: gtk3IconCombo.combo.model[gtk3IconCombo.combo.currentIndex]?.value ?? ""
                        Layout.fillWidth: true
                    }
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
                        CursorThemePreview {
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
                    IconThemePreview {
                        themeName: gtk4IconCombo.combo.model[gtk4IconCombo.combo.currentIndex]?.value ?? ""
                        Layout.fillWidth: true
                    }
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
