import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760
    readonly property bool settingsApp: Quickshell.env("II_SETTINGS_APP") === "1"

    property string _hostname: ""
    property string _memory: ""
    property string _uptime: ""

    readonly property var realOutputDevices: Audio.outputDevices.filter(d => d.name !== "qs_mono_out")

    PwObjectTracker {
        objects: root.realOutputDevices
    }

    component SummaryCard: Rectangle {
        id: summaryCard
        required property string title
        required property string icon
        property string subtitle: ""
        property string detail: ""

        Layout.fillWidth: true
        implicitHeight: 118
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 6

            RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: summaryCard.icon
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: summaryCard.title
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                }
            }

            StyledText {
                text: summaryCard.subtitle
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.Wrap
            }

            StyledText {
                visible: text.length > 0
                text: summaryCard.detail
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }

    Process {
        running: true
        command: ["bash", "-c",
            "echo \"hostname:$(hostname 2>/dev/null)\"; " +
            "awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf \"memory:%.1f / %.1f GiB\\n\",(t-a)/1048576,t/1048576}' /proc/meminfo; " +
            "echo \"uptime:$(uptime -p 2>/dev/null | sed 's/^up //' || echo Unknown)\""
        ]
        stdout: SplitParser {
            onRead: data => {
                const idx = data.indexOf(':')
                if (idx < 0) return
                const key = data.slice(0, idx)
                const val = data.slice(idx + 1)
                switch (key) {
                    case 'hostname': root._hostname = val; break
                    case 'memory':   root._memory   = val; break
                    case 'uptime':   root._uptime   = val; break
                }
            }
        }
    }

    // ── Welcome ───────────────────────────────────────────────────────────
    ContentSection {
        icon: "person"
        title: `${SystemInfo.username} \u2014 ${SystemInfo.distroName}`

        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Layout.topMargin: 4
            Layout.bottomMargin: 4

            // Wallpaper preview
            Rectangle {
                implicitWidth: 200
                implicitHeight: 112
                radius: Appearance.rounding.normal
                color: "transparent"
                clip: true

                StyledImage {
                    anchors.fill: parent
                    sourceSize.width: parent.implicitWidth
                    sourceSize.height: parent.implicitHeight
                    fillMode: Image.PreserveAspectCrop
                    source: Config.options.background.wallpaperPath
                    cache: false
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                // Dark / Light toggle
                RowLayout {
                    spacing: 6
                    Layout.fillWidth: true

                    Repeater {
                        model: [{ dark: false, icon: "light_mode", label: Translation.tr("Light") },
                                { dark: true,  icon: "dark_mode",  label: Translation.tr("Dark")  }]
                        delegate: RippleButton {
                            id: modeToggleButton
                            required property var modelData
                            readonly property color colText: toggled ? colForegroundToggled : Appearance.colors.colOnLayer2
                            Layout.fillWidth: true
                            implicitHeight: 48
                            buttonRadius: Appearance.rounding.normal
                            toggled: Appearance.m3colors.darkmode === modelData.dark
                            colBackground: Appearance.colors.colLayer2
                            onClicked: Quickshell.execDetached(["bash", "-c",
                                `${Directories.wallpaperSwitchScriptPath} --mode ${modelData.dark ? "dark" : "light"} --noswitch`])
                            contentItem: ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 2
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    iconSize: 22
                                    text: modelData.icon
                                    color: modeToggleButton.colText
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: modeToggleButton.colText
                                }
                            }
                        }
                    }
                }

                // Wallpaper picker
                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "wallpaper"
                    mainText: Translation.tr("Change wallpaper")
                    onClicked: Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode)
                }
            }
        }
    }

    ContentSection {
        icon: "stylus"
        title: Translation.tr("Desktop theme stack")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("This settings app now exposes the theme layers below Quickshell as well, so you can see your GTK files, GNOME interface values, and KDE or Qt theme files in one place.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            SummaryCard {
                title: Translation.tr("GTK")
                icon: "palette"
                subtitle: `${DesktopThemeSettings.gtk4Theme || DesktopThemeSettings.gtk3Theme || "-"}`
                detail: `${Translation.tr("Icons")}: ${DesktopThemeSettings.gtk4IconTheme || DesktopThemeSettings.gtk3IconTheme || "-"}`
            }

            SummaryCard {
                title: Translation.tr("GNOME")
                icon: "deployed_code"
                subtitle: DesktopThemeSettings.gnomeGtkTheme || "-"
                detail: `${Translation.tr("Scheme")}: ${DesktopThemeSettings.gnomeColorScheme || "-"}`
            }

            SummaryCard {
                title: Translation.tr("KDE / Qt")
                icon: "widgets"
                subtitle: DesktopThemeSettings.kdeColorScheme || "-"
                detail: `${Translation.tr("Kvantum")}: ${DesktopThemeSettings.kvantumTheme || "-"}`
            }
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "edit_document"
                mainText: Translation.tr("GTK files")
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
                mainText: Translation.tr("Refresh system theme state")
                onClicked: DesktopThemeSettings.refreshAll()
            }
        }
    }

    // ── Audio ─────────────────────────────────────────────────────────────
    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Audio output")

        StyledComboBox {
            Layout.fillWidth: true
            buttonIcon: "speaker"
            textRole: "displayName"
            model: root.realOutputDevices.map(d => ({ displayName: Audio.friendlyDeviceName(d) }))
            currentIndex: Math.max(0, root.realOutputDevices.findIndex(d => d.name === (Audio.sink?.name ?? "")))
            onActivated: index => Audio.setDefaultSink(root.realOutputDevices[index])
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                buttonRadius: Appearance.rounding.full
                implicitWidth: 40; implicitHeight: 40
                onClicked: Audio.toggleMute()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
            }

            StyledSlider {
                Layout.fillWidth: true
                from: 0; to: 1.54
                value: Audio.value
                configuration: StyledSlider.Configuration.M
                usePercentTooltip: false
                tooltipContent: `${Math.round(value * 100)}%`
                onMoved: { if (Audio.sink?.audio) Audio.sink.audio.volume = value }
            }

            StyledText {
                text: `${Math.round(Audio.value * 100)}%`
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    // ── System snapshot ───────────────────────────────────────────────────
    ContentSection {
        icon: "monitor_heart"
        title: Translation.tr("System")

        ConfigRow {
            uniform: true

            ContentSubsection {
                title: Translation.tr("Memory")
                StyledText {
                    text: root._memory || "\u2026"
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
            }

            ContentSubsection {
                title: Translation.tr("Uptime")
                StyledText {
                    text: root._uptime || "\u2026"
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
            }

            ContentSubsection {
                title: Translation.tr("Host")
                StyledText {
                    text: root._hostname || "\u2026"
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
            }
        }
    }
}
