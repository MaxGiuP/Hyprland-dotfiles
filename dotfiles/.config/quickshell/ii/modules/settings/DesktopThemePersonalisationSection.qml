import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentSection {
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
                `theme="${cursorPreviewItem.themeName}"
                 for dir in "$HOME/.icons" "/usr/share/icons"; do
                   f="$dir/$theme/hyprcursors/left_ptr.hlc"
                   [ -f "$f" ] || continue
                   out="/tmp/qs-cursor-preview-$theme.svg"
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
                `theme="${iconPreviewItem.themeName}"
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

        ContentSubsection {
title: Translation.tr("Wallpaper mode")

ConfigSelectionArray {
    currentValue: Config.options.background.wallpaperMode ?? "static"
    onSelected: newValue => Wallpapers.setWallpaperMode(newValue)
    options: [
        { value: "static", displayName: Translation.tr("Static"), icon: "image" },
        { value: "dynamic", displayName: Translation.tr("Dynamic"), icon: "wallpaper_slideshow" }
    ]
}

StyledText {
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    color: Appearance.colors.colSubtext
    text: (Config.options.background.wallpaperMode ?? "static") === "dynamic"
        ? Translation.tr("Dynamic picks a random wallpaper from morning/day/evening/night folders using the local sunrise and sunset schedule, then applies colours through the same pipeline as static wallpapers.")
        : Translation.tr("Static keeps the current wallpaper until you pick another one.")
}

ConfigRow {
    uniform: true

    RippleButtonWithIcon {
        Layout.fillWidth: true
        materialIcon: "wallpaper"
        mainText: Translation.tr("Choose wallpaper")
        onClicked: Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode)
    }

    RippleButtonWithIcon {
        Layout.fillWidth: true
        materialIcon: "shuffle"
        mainText: Translation.tr("Random from folder")
        onClicked: Wallpapers.randomFromCurrentFolder(Appearance.m3colors.darkmode)
    }

    RippleButtonWithIcon {
        Layout.fillWidth: true
        materialIcon: "skip_next"
        mainText: Translation.tr("Next dynamic")
        onClicked: Wallpapers.dynamicNext()
        StyledToolTip { text: Translation.tr("Applies one wallpaper from the dynamic folder now without enabling rotation.") }
    }
}

ContentSubsection {
    visible: (Config.options.background.wallpaperMode ?? "static") === "dynamic"
    title: Translation.tr("Dynamic wallpaper settings")

    ConfigRow {
        uniform: true

        ConfigSwitch {
            buttonIcon: "routine"
            text: Translation.tr("Auto light/dark")
            checked: Config.options.background.dynamic.autoMode
            onCheckedChanged: Config.options.background.dynamic.autoMode = checked
        }

        ConfigSwitch {
            buttonIcon: "wb_twilight"
            text: Translation.tr("Use period folders")
            checked: Config.options.background.dynamic.preferTime
            onCheckedChanged: Config.options.background.dynamic.preferTime = checked
        }
    }

    ConfigSelectionArray {
        currentValue: Config.options.background.dynamic.scheduleMode ?? "sun"
        onSelected: newValue => Config.options.background.dynamic.scheduleMode = newValue
        options: [
            { value: "sun", displayName: Translation.tr("Sunrise/sunset"), icon: "wb_twilight" },
            { value: "manual", displayName: Translation.tr("Custom times"), icon: "schedule" }
        ]
    }

    ConfigRow {
        visible: (Config.options.background.dynamic.scheduleMode ?? "sun") === "manual"
        uniform: true

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            StyledText {
                text: Translation.tr("Morning starts")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
            MaterialTextField {
                Layout.fillWidth: true
                text: Config.options.background.dynamic.morningTime ?? "06:00"
                placeholderText: "06:00"
                onAccepted: Config.options.background.dynamic.morningTime = text
                onEditingFinished: Config.options.background.dynamic.morningTime = text
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            StyledText {
                text: Translation.tr("Day starts")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
            MaterialTextField {
                Layout.fillWidth: true
                text: Config.options.background.dynamic.dayTime ?? "10:30"
                placeholderText: "10:30"
                onAccepted: Config.options.background.dynamic.dayTime = text
                onEditingFinished: Config.options.background.dynamic.dayTime = text
            }
        }
    }

    ConfigRow {
        visible: (Config.options.background.dynamic.scheduleMode ?? "sun") === "manual"
        uniform: true

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            StyledText {
                text: Translation.tr("Evening starts")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
            MaterialTextField {
                Layout.fillWidth: true
                text: Config.options.background.dynamic.eveningTime ?? "17:30"
                placeholderText: "17:30"
                onAccepted: Config.options.background.dynamic.eveningTime = text
                onEditingFinished: Config.options.background.dynamic.eveningTime = text
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            StyledText {
                text: Translation.tr("Night starts")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
            MaterialTextField {
                Layout.fillWidth: true
                text: Config.options.background.dynamic.nightTime ?? "21:30"
                placeholderText: "21:30"
                onAccepted: Config.options.background.dynamic.nightTime = text
                onEditingFinished: Config.options.background.dynamic.nightTime = text
            }
        }
    }

    StyledText {
        visible: (Config.options.background.dynamic.scheduleMode ?? "sun") === "manual"
        Layout.fillWidth: true
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.Wrap
        text: Translation.tr("Use 24-hour HH:MM times. Each time is the start of that wallpaper period; night can continue past midnight until morning starts.")
    }

    ConfigSpinBox {
        icon: "timer"
        text: Translation.tr("Rotation interval (minutes)")
        value: Math.max(1, Math.round(Config.options.background.dynamic.intervalSeconds / 60))
        from: 1
        to: 240
        stepSize: 1
        onValueChanged: Config.options.background.dynamic.intervalSeconds = value * 60
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        StyledText {
            text: Translation.tr("Dynamic folder")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        MaterialTextField {
            id: dynamicWallpaperDirectoryField
            Layout.fillWidth: true
            text: Config.options.background.dynamic.directory
            placeholderText: `${Directories.pictures}/Wallpapers/dynamic-system`
            onAccepted: Config.options.background.dynamic.directory = text
            onEditingFinished: Config.options.background.dynamic.directory = text
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        StyledText {
            text: Translation.tr("Sunrise/sunset location")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        MaterialTextField {
            Layout.fillWidth: true
            text: Config.options.background.dynamic.city
            placeholderText: "Abingdon, Oxfordshire"
            onAccepted: Config.options.background.dynamic.city = text
            onEditingFinished: Config.options.background.dynamic.city = text
        }
    }

    ConfigRow {
        uniform: true

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            StyledText {
                text: Translation.tr("Latitude")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
            MaterialTextField {
                Layout.fillWidth: true
                text: String(Config.options.background.dynamic.latitude)
                placeholderText: "51.6715"
                onAccepted: Config.options.background.dynamic.latitude = parseFloat(text)
                onEditingFinished: Config.options.background.dynamic.latitude = parseFloat(text)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            StyledText {
                text: Translation.tr("Longitude")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
            MaterialTextField {
                Layout.fillWidth: true
                text: String(Config.options.background.dynamic.longitude)
                placeholderText: "-1.2780"
                onAccepted: Config.options.background.dynamic.longitude = parseFloat(text)
                onEditingFinished: Config.options.background.dynamic.longitude = parseFloat(text)
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.Wrap
        text: (Config.options.background.dynamic.scheduleMode ?? "sun") === "manual"
            ? Translation.tr("Folder must contain morning, day, evening and night subfolders. Custom times decide when each folder is used.")
            : Translation.tr("Folder must contain morning, day, evening and night subfolders. Location is used locally to calculate sunrise and sunset; no network call is needed during rotation.")
    }

    ConfigRow {
        uniform: true

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: Wallpapers.dynamicRunning ? "pause" : "play_arrow"
            mainText: Wallpapers.dynamicRunning ? Translation.tr("Stop dynamic") : Translation.tr("Start dynamic")
            onClicked: Wallpapers.dynamicRunning ? Wallpapers.stopDynamic() : Wallpapers.startDynamic()
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh status")
            onClicked: Wallpapers.refreshDynamicStatus()
        }
    }

    StyledText {
        Layout.fillWidth: true
        color: Wallpapers.dynamicRunning ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        text: Translation.tr("Status: %1").arg(Wallpapers.dynamicStatus)
        wrapMode: Text.Wrap
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

            DesktopThemeCursorPreview {
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

DesktopThemeIconPreview {
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
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: Wallpapers.preload(modelData)
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
