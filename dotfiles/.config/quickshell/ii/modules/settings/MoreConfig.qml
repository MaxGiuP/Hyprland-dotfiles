import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760

    function parseJson(text, fallback) {
        try {
            return JSON.parse(text);
        } catch (error) {
            return fallback;
        }
    }

    function normalizedJson(value) {
        return JSON.stringify(value, null, 2);
    }

    ContentSection {
        icon: "apps"
        title: Translation.tr("Apps")

        ContentSubsection {
            title: Translation.tr("System app commands")
            tooltip: Translation.tr("Commands used by shell actions and shortcuts.")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Bluetooth settings command")
                text: Config.options.apps.bluetooth
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.apps.bluetooth = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Change password command")
                text: Config.options.apps.changePassword
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.apps.changePassword = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Network settings command")
                text: Config.options.apps.network
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.apps.network = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Ethernet settings command")
                text: Config.options.apps.networkEthernet
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.apps.networkEthernet = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("User management command")
                text: Config.options.apps.manageUser
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.apps.manageUser = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Task manager command")
                text: Config.options.apps.taskManager
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.apps.taskManager = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Terminal command")
                text: Config.options.apps.terminal
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.apps.terminal = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("System update command")
                text: Config.options.apps.update
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.apps.update = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Volume mixer command")
                text: Config.options.apps.volumeMixer
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.apps.volumeMixer = text
            }
        }
    }

    ContentSection {
        icon: "dock_to_bottom"
        title: Translation.tr("Dock & Launcher")

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Dock height")
                value: Config.options.dock.height
                from: 36
                to: 160
                stepSize: 2
                onValueChanged: Config.options.dock.height = value
            }
            ConfigSpinBox {
                icon: "gesture"
                text: Translation.tr("Reveal edge height")
                value: Config.options.dock.hoverRegionHeight
                from: 1
                to: 40
                stepSize: 1
                onValueChanged: Config.options.dock.hoverRegionHeight = value
            }
        }

        ContentSubsection {
            title: Translation.tr("Pinned apps")
            tooltip: Translation.tr("JSON array of desktop IDs shown in the dock and launcher.")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("[\"org.kde.dolphin\", \"kitty\"]")
                text: root.normalizedJson(Config.options.dock.pinnedApps)
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    const parsed = root.parseJson(text, null);
                    if (parsed !== null && Array.isArray(parsed))
                        Config.options.dock.pinnedApps = parsed;
                }
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("[\"^steam_app_.*$\"]")
                text: root.normalizedJson(Config.options.dock.ignoredAppRegexes)
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    const parsed = root.parseJson(text, null);
                    if (parsed !== null && Array.isArray(parsed))
                        Config.options.dock.ignoredAppRegexes = parsed;
                }
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("[\"org.kde.dolphin\", \"kitty\", \"cmake-gui\"]")
                text: root.normalizedJson(Config.options.launcher.pinnedApps)
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    const parsed = root.parseJson(text, null);
                    if (parsed !== null && Array.isArray(parsed))
                        Config.options.launcher.pinnedApps = parsed;
                }
            }
        }
    }

    ContentSection {
        icon: "toolbar"
        title: Translation.tr("Bar")

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "swap_vert"
                text: Translation.tr("Auto-hide hover width")
                value: Config.options.bar.autoHide.hoverRegionWidth
                from: 1
                to: 40
                stepSize: 1
                onValueChanged: Config.options.bar.autoHide.hoverRegionWidth = value
            }
            ConfigSpinBox {
                icon: "warning"
                text: Translation.tr("CPU warning %")
                value: Config.options.bar.resources.cpuWarningThreshold
                from: 1
                to: 100
                stepSize: 1
                onValueChanged: Config.options.bar.resources.cpuWarningThreshold = value
            }
        }

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "memory"
                text: Translation.tr("Memory warning %")
                value: Config.options.bar.resources.memoryWarningThreshold
                from: 1
                to: 100
                stepSize: 1
                onValueChanged: Config.options.bar.resources.memoryWarningThreshold = value
            }
            ConfigSpinBox {
                icon: "swap_horiz"
                text: Translation.tr("Swap warning %")
                value: Config.options.bar.resources.swapWarningThreshold
                from: 1
                to: 100
                stepSize: 1
                onValueChanged: Config.options.bar.resources.swapWarningThreshold = value
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "open_with"
                text: Translation.tr("Push windows on auto-hide")
                checked: Config.options.bar.autoHide.pushWindows
                onCheckedChanged: Config.options.bar.autoHide.pushWindows = checked
            }
            ConfigSwitch {
                buttonIcon: "shadow"
                text: Translation.tr("Floating style shadow")
                checked: Config.options.bar.floatStyleShadow
                onCheckedChanged: Config.options.bar.floatStyleShadow = checked
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "gallery_thumbnail"
                text: Translation.tr("Show bar background")
                checked: Config.options.bar.showBackground
                onCheckedChanged: Config.options.bar.showBackground = checked
            }
            ConfigSwitch {
                buttonIcon: "view_timeline"
                text: Translation.tr("Verbose resources")
                checked: Config.options.bar.verbose
                onCheckedChanged: Config.options.bar.verbose = checked
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "memory_alt"
                text: Translation.tr("Always show CPU")
                checked: Config.options.bar.resources.alwaysShowCpu
                onCheckedChanged: Config.options.bar.resources.alwaysShowCpu = checked
            }
            ConfigSwitch {
                buttonIcon: "swap_driving_apps"
                text: Translation.tr("Always show swap")
                checked: Config.options.bar.resources.alwaysShowSwap
                onCheckedChanged: Config.options.bar.resources.alwaysShowSwap = checked
            }
        }

        ConfigSwitch {
            buttonIcon: "format_letter_spacing"
            text: Translation.tr("Use Nerd Font workspace labels")
            checked: Config.options.bar.workspaces.useNerdFont
            onCheckedChanged: Config.options.bar.workspaces.useNerdFont = checked
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Top-left icon name")
            text: Config.options.bar.topLeftIcon
            wrapMode: TextEdit.NoWrap
            onTextChanged: Config.options.bar.topLeftIcon = text
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("[\"eDP-1\", \"HDMI-A-1\"]")
            text: root.normalizedJson(Config.options.bar.screenList)
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                const parsed = root.parseJson(text, null);
                if (parsed !== null && Array.isArray(parsed))
                    Config.options.bar.screenList = parsed;
            }
        }
    }

    ContentSection {
        icon: "search"
        title: Translation.tr("Search")

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Non-app result delay (ms)")
                value: Config.options.search.nonAppResultDelay
                from: 0
                to: 500
                stepSize: 5
                onValueChanged: Config.options.search.nonAppResultDelay = value
            }
            ConfigSwitch {
                buttonIcon: "bolt"
                text: Translation.tr("Show default actions without prefix")
                checked: Config.options.search.prefix.showDefaultActionsWithoutPrefix
                onCheckedChanged: Config.options.search.prefix.showDefaultActionsWithoutPrefix = checked
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "filter_center_focus"
                text: Translation.tr("Use circle selection for image search")
                checked: Config.options.search.imageSearch.useCircleSelection
                onCheckedChanged: Config.options.search.imageSearch.useCircleSelection = checked
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("App search prefix")
            text: Config.options.search.prefix.app
            wrapMode: TextEdit.NoWrap
            onTextChanged: Config.options.search.prefix.app = text
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Image search engine base URL")
            text: Config.options.search.imageSearch.imageSearchEngineBaseUrl
            wrapMode: TextEdit.NoWrap
            onTextChanged: Config.options.search.imageSearch.imageSearchEngineBaseUrl = text
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("[\"quora.com\", \"facebook.com\"]")
            text: root.normalizedJson(Config.options.search.excludedSites)
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                const parsed = root.parseJson(text, null);
                if (parsed !== null && Array.isArray(parsed))
                    Config.options.search.excludedSites = parsed;
            }
        }
    }

    ContentSection {
        icon: "right_panel_open"
        title: Translation.tr("Sidebar & Overview")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "dock_to_right"
                text: Translation.tr("Keep right sidebar loaded")
                checked: Config.options.sidebar.keepRightSidebarLoaded
                onCheckedChanged: Config.options.sidebar.keepRightSidebarLoaded = checked
            }
            ConfigSwitch {
                buttonIcon: "animation"
                text: Translation.tr("AI text fade-in")
                checked: Config.options.sidebar.ai.textFadeIn
                onCheckedChanged: Config.options.sidebar.ai.textFadeIn = checked
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "translate"
                text: Translation.tr("Enable sidebar translator")
                checked: Config.options.sidebar.translator.enable
                onCheckedChanged: Config.options.sidebar.translator.enable = checked
            }
            ConfigSpinBox {
                icon: "hourglass_top"
                text: Translation.tr("Translator delay (ms)")
                value: Config.options.sidebar.translator.delay
                from: 0
                to: 2000
                stepSize: 25
                onValueChanged: Config.options.sidebar.translator.delay = value
            }
        }

        ContentSubsection {
            title: Translation.tr("Corner open")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "gesture_select"
                    text: Translation.tr("Enable corner open")
                    checked: Config.options.sidebar.cornerOpen.enable
                    onCheckedChanged: Config.options.sidebar.cornerOpen.enable = checked
                }
                ConfigSwitch {
                    buttonIcon: "south"
                    text: Translation.tr("Use bottom corner")
                    checked: Config.options.sidebar.cornerOpen.bottom
                    onCheckedChanged: Config.options.sidebar.cornerOpen.bottom = checked
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "mouse"
                    text: Translation.tr("Scroll values in corner")
                    checked: Config.options.sidebar.cornerOpen.valueScroll
                    onCheckedChanged: Config.options.sidebar.cornerOpen.valueScroll = checked
                }
                ConfigSwitch {
                    buttonIcon: "ads_click"
                    text: Translation.tr("Clickless open")
                    checked: Config.options.sidebar.cornerOpen.clickless
                    onCheckedChanged: Config.options.sidebar.cornerOpen.clickless = checked
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "visibility"
                    text: Translation.tr("Visualize trigger region")
                    checked: Config.options.sidebar.cornerOpen.visualize
                    onCheckedChanged: Config.options.sidebar.cornerOpen.visualize = checked
                }
                ConfigSwitch {
                    buttonIcon: "last_page"
                    text: Translation.tr("Stop clickless at corner end")
                    checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
                    onCheckedChanged: Config.options.sidebar.cornerOpen.clicklessCornerEnd = checked
                }
            }

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "width"
                    text: Translation.tr("Corner width")
                    value: Config.options.sidebar.cornerOpen.cornerRegionWidth
                    from: 1
                    to: 1000
                    stepSize: 5
                    onValueChanged: Config.options.sidebar.cornerOpen.cornerRegionWidth = value
                }
                ConfigSpinBox {
                    icon: "height"
                    text: Translation.tr("Corner height")
                    value: Config.options.sidebar.cornerOpen.cornerRegionHeight
                    from: 1
                    to: 500
                    stepSize: 1
                    onValueChanged: Config.options.sidebar.cornerOpen.cornerRegionHeight = value
                }
            }

            ConfigSpinBox {
                icon: "vertical_align_center"
                text: Translation.tr("Clickless vertical offset")
                value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = value
            }
        }

        ContentSubsection {
            title: Translation.tr("Quick controls")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "tune"
                    text: Translation.tr("Enable quick sliders")
                    checked: Config.options.sidebar.quickSliders.enable
                    onCheckedChanged: Config.options.sidebar.quickSliders.enable = checked
                }
                ConfigSwitch {
                    buttonIcon: "mic"
                    text: Translation.tr("Show mic slider")
                    checked: Config.options.sidebar.quickSliders.showMic
                    onCheckedChanged: Config.options.sidebar.quickSliders.showMic = checked
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("Show volume slider")
                    checked: Config.options.sidebar.quickSliders.showVolume
                    onCheckedChanged: Config.options.sidebar.quickSliders.showVolume = checked
                }
                ConfigSwitch {
                    buttonIcon: "light_mode"
                    text: Translation.tr("Show brightness slider")
                    checked: Config.options.sidebar.quickSliders.showBrightness
                    onCheckedChanged: Config.options.sidebar.quickSliders.showBrightness = checked
                }
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Quick toggle style")
                text: Config.options.sidebar.quickToggles.style
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.sidebar.quickToggles.style = text
            }

            ConfigSpinBox {
                icon: "view_comfy_alt"
                text: Translation.tr("Android toggle columns")
                value: Config.options.sidebar.quickToggles.android.columns
                from: 1
                to: 10
                stepSize: 1
                onValueChanged: Config.options.sidebar.quickToggles.android.columns = value
            }
        }

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "grid_view"
                text: Translation.tr("Overview rows")
                value: Config.options.overview.rows
                from: 1
                to: 8
                stepSize: 1
                onValueChanged: Config.options.overview.rows = value
            }
            ConfigSpinBox {
                icon: "view_module"
                text: Translation.tr("Overview columns")
                value: Config.options.overview.columns
                from: 1
                to: 12
                stepSize: 1
                onValueChanged: Config.options.overview.columns = value
            }
        }

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "zoom_out_map"
                text: Translation.tr("Overview scale (%)")
                value: Config.options.overview.scale * 100
                from: 5
                to: 100
                stepSize: 1
                onValueChanged: Config.options.overview.scale = value / 100
            }
            ConfigSpinBox {
                icon: "opacity"
                text: Translation.tr("Overlay click-through opacity (%)")
                value: Config.options.overlay.clickthroughOpacity * 100
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: Config.options.overlay.clickthroughOpacity = value / 100
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "align_horizontal_right"
                text: Translation.tr("Order workspaces right to left")
                checked: Config.options.overview.orderRightLeft
                onCheckedChanged: Config.options.overview.orderRightLeft = checked
            }
            ConfigSwitch {
                buttonIcon: "vertical_align_bottom"
                text: Translation.tr("Order workspaces bottom up")
                checked: Config.options.overview.orderBottomUp
                onCheckedChanged: Config.options.overview.orderBottomUp = checked
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "center_focus_strong"
                text: Translation.tr("Center overview icons")
                checked: Config.options.overview.centerIcons
                onCheckedChanged: Config.options.overview.centerIcons = checked
            }
            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Enable overview")
                checked: Config.options.overview.enable
                onCheckedChanged: Config.options.overview.enable = checked
            }
        }
    }

    ContentSection {
        icon: "tungsten"
        title: Translation.tr("Input, Display & Media")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "touchpad_mouse"
                text: Translation.tr("Faster touchpad scroll")
                checked: Config.options.interactions.scrolling.fasterTouchpadScroll
                onCheckedChanged: Config.options.interactions.scrolling.fasterTouchpadScroll = checked
            }
            ConfigSwitch {
                buttonIcon: "border_outer"
                text: Translation.tr("Dead pixel workaround")
                checked: Config.options.interactions.deadPixelWorkaround.enable
                onCheckedChanged: Config.options.interactions.deadPixelWorkaround.enable = checked
            }
        }

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "mouse"
                text: Translation.tr("Mouse scroll threshold")
                value: Config.options.interactions.scrolling.mouseScrollDeltaThreshold
                from: 1
                to: 1000
                stepSize: 5
                onValueChanged: Config.options.interactions.scrolling.mouseScrollDeltaThreshold = value
            }
            ConfigSpinBox {
                icon: "arrow_downward"
                text: Translation.tr("Mouse scroll factor")
                value: Config.options.interactions.scrolling.mouseScrollFactor
                from: 1
                to: 1000
                stepSize: 5
                onValueChanged: Config.options.interactions.scrolling.mouseScrollFactor = value
            }
        }

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "touch_app"
                text: Translation.tr("Touchpad scroll factor")
                value: Config.options.interactions.scrolling.touchpadScrollFactor
                from: 1
                to: 2000
                stepSize: 10
                onValueChanged: Config.options.interactions.scrolling.touchpadScrollFactor = value
            }
            ConfigSpinBox {
                icon: "schedule"
                text: Translation.tr("OSD timeout (ms)")
                value: Config.options.osd.timeout
                from: 100
                to: 10000
                stepSize: 100
                onValueChanged: Config.options.osd.timeout = value
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "library_music"
                text: Translation.tr("Filter duplicate media players")
                checked: Config.options.media.filterDuplicatePlayers
                onCheckedChanged: Config.options.media.filterDuplicatePlayers = checked
            }
            ConfigSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Pin on-screen keyboard at startup")
                checked: Config.options.osk.pinnedOnStartup
                onCheckedChanged: Config.options.osk.pinnedOnStartup = checked
            }
        }

        ContentSubsection {
            title: Translation.tr("On-screen keyboard")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Keyboard layout")
                text: Config.options.osk.layout
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.osk.layout = text
            }
        }
    }

    ContentSection {
        icon: "globe"
        title: Translation.tr("Locale, Updates & Safety")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Calendar locale")
            text: Config.options.calendar.locale
            wrapMode: TextEdit.NoWrap
            onTextChanged: Config.options.calendar.locale = text
        }

        ContentSubsection {
            title: Translation.tr("Translator")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Translation engine")
                text: Config.options.language.translator.engine
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.language.translator.engine = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Source language")
                text: Config.options.language.translator.sourceLanguage
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.language.translator.sourceLanguage = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Target language")
                text: Config.options.language.translator.targetLanguage
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.language.translator.targetLanguage = text
            }
        }

        ContentSubsection {
            title: Translation.tr("Updates and sounds")

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "update"
                    text: Translation.tr("Check interval (min)")
                    value: Config.options.updates.checkInterval
                    from: 1
                    to: 1440
                    stepSize: 5
                    onValueChanged: Config.options.updates.checkInterval = value
                }
                ConfigSpinBox {
                    icon: "priority_high"
                    text: Translation.tr("Advise update threshold")
                    value: Config.options.updates.adviseUpdateThreshold
                    from: 1
                    to: 1000
                    stepSize: 5
                    onValueChanged: Config.options.updates.adviseUpdateThreshold = value
                }
            }

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "warning"
                    text: Translation.tr("Strong advice threshold")
                    value: Config.options.updates.stronglyAdviseUpdateThreshold
                    from: 1
                    to: 2000
                    stepSize: 10
                    onValueChanged: Config.options.updates.stronglyAdviseUpdateThreshold = value
                }
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Sound theme")
                text: Config.options.sounds.theme
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.sounds.theme = text
            }
        }

        ContentSubsection {
            title: Translation.tr("Content safety")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("[\"airport\", \"cafe\", \"public\"]")
                text: root.normalizedJson(Config.options.workSafety.triggerCondition.networkNameKeywords)
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    const parsed = root.parseJson(text, null);
                    if (parsed !== null && Array.isArray(parsed))
                        Config.options.workSafety.triggerCondition.networkNameKeywords = parsed;
                }
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("[\"sensitive\", \"private\", \"spoiler\"]")
                text: root.normalizedJson(Config.options.workSafety.triggerCondition.fileKeywords)
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    const parsed = root.parseJson(text, null);
                    if (parsed !== null && Array.isArray(parsed))
                        Config.options.workSafety.triggerCondition.fileKeywords = parsed;
                }
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("[\"sensitive\", \"private\"]")
                text: root.normalizedJson(Config.options.workSafety.triggerCondition.linkKeywords)
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    const parsed = root.parseJson(text, null);
                    if (parsed !== null && Array.isArray(parsed))
                        Config.options.workSafety.triggerCondition.linkKeywords = parsed;
                }
            }
        }
    }

    ContentSection {
        icon: "screenshot_frame_2"
        title: Translation.tr("Region selector")

        ContentSubsection {
            title: Translation.tr("Target hints")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "label"
                    text: Translation.tr("Show labels")
                    checked: Config.options.regionSelector.targetRegions.showLabel
                    onCheckedChanged: Config.options.regionSelector.targetRegions.showLabel = checked
                }
                ConfigSwitch {
                    buttonIcon: "edit_square"
                    text: Translation.tr("Use Satty for annotation")
                    checked: Config.options.regionSelector.annotation.useSatty
                    onCheckedChanged: Config.options.regionSelector.annotation.useSatty = checked
                }
            }

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "opacity"
                    text: Translation.tr("Region opacity (%)")
                    value: Config.options.regionSelector.targetRegions.opacity * 100
                    from: 0
                    to: 100
                    stepSize: 1
                    onValueChanged: Config.options.regionSelector.targetRegions.opacity = value / 100
                }
                ConfigSpinBox {
                    icon: "image"
                    text: Translation.tr("Content opacity (%)")
                    value: Config.options.regionSelector.targetRegions.contentRegionOpacity * 100
                    from: 0
                    to: 100
                    stepSize: 1
                    onValueChanged: Config.options.regionSelector.targetRegions.contentRegionOpacity = value / 100
                }
            }

            ConfigSpinBox {
                icon: "padding"
                text: Translation.tr("Selection padding")
                value: Config.options.regionSelector.targetRegions.selectionPadding
                from: 0
                to: 50
                stepSize: 1
                onValueChanged: Config.options.regionSelector.targetRegions.selectionPadding = value
            }
        }

        ContentSubsection {
            title: Translation.tr("Shapes")

            ConfigSwitch {
                buttonIcon: "show_chart"
                text: Translation.tr("Show aim lines for rect selection")
                checked: Config.options.regionSelector.rect.showAimLines
                onCheckedChanged: Config.options.regionSelector.rect.showAimLines = checked
            }

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "line_weight"
                    text: Translation.tr("Circle stroke width")
                    value: Config.options.regionSelector.circle.strokeWidth
                    from: 1
                    to: 50
                    stepSize: 1
                    onValueChanged: Config.options.regionSelector.circle.strokeWidth = value
                }
                ConfigSpinBox {
                    icon: "padding"
                    text: Translation.tr("Circle padding")
                    value: Config.options.regionSelector.circle.padding
                    from: 0
                    to: 100
                    stepSize: 1
                    onValueChanged: Config.options.regionSelector.circle.padding = value
                }
            }
        }
    }

    ContentSection {
        icon: "schedule"
        title: Translation.tr("Time, Shell & Misc")

        ContentSubsection {
            title: Translation.tr("Date and Pomodoro")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Short date format")
                text: Config.options.time.shortDateFormat
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.time.shortDateFormat = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Date with year format")
                text: Config.options.time.dateWithYearFormat
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.time.dateWithYearFormat = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Date format")
                text: Config.options.time.dateFormat
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.time.dateFormat = text
            }

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Focus (s)")
                    value: Config.options.time.pomodoro.focus
                    from: 60
                    to: 14400
                    stepSize: 60
                    onValueChanged: Config.options.time.pomodoro.focus = value
                }
                ConfigSpinBox {
                    icon: "free_breakfast"
                    text: Translation.tr("Break (s)")
                    value: Config.options.time.pomodoro.breakTime
                    from: 60
                    to: 7200
                    stepSize: 60
                    onValueChanged: Config.options.time.pomodoro.breakTime = value
                }
            }

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "repeat"
                    text: Translation.tr("Cycles before long break")
                    value: Config.options.time.pomodoro.cyclesBeforeLongBreak
                    from: 1
                    to: 20
                    stepSize: 1
                    onValueChanged: Config.options.time.pomodoro.cyclesBeforeLongBreak = value
                }
                ConfigSpinBox {
                    icon: "hotel"
                    text: Translation.tr("Long break (s)")
                    value: Config.options.time.pomodoro.longBreak
                    from: 60
                    to: 14400
                    stepSize: 60
                    onValueChanged: Config.options.time.pomodoro.longBreak = value
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Shell behavior")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "cancel_presentation"
                    text: Translation.tr("Auto-kill notification daemons")
                    checked: Config.options.conflictKiller.autoKillNotificationDaemons
                    onCheckedChanged: Config.options.conflictKiller.autoKillNotificationDaemons = checked
                }
                ConfigSwitch {
                    buttonIcon: "crop_square"
                    text: Translation.tr("Auto-kill tray conflicts")
                    checked: Config.options.conflictKiller.autoKillTrays
                    onCheckedChanged: Config.options.conflictKiller.autoKillTrays = checked
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "dock_window"
                    text: Translation.tr("Show shell titlebars")
                    checked: Config.options.windows.showTitlebar
                    onCheckedChanged: Config.options.windows.showTitlebar = checked
                }
                ConfigSwitch {
                    buttonIcon: "format_align_center"
                    text: Translation.tr("Center shell titles")
                    checked: Config.options.windows.centerTitle
                    onCheckedChanged: Config.options.windows.centerTitle = checked
                }
            }

            ConfigSpinBox {
                icon: "hourglass_bottom"
                text: Translation.tr("Race condition delay (ms)")
                value: Config.options.hacks.arbitraryRaceConditionDelay
                from: 0
                to: 1000
                stepSize: 5
                onValueChanged: Config.options.hacks.arbitraryRaceConditionDelay = value
            }

            ConfigSpinBox {
                icon: "history"
                text: Translation.tr("Resource history length")
                value: Config.options.resources.historyLength
                from: 1
                to: 1000
                stepSize: 5
                onValueChanged: Config.options.resources.historyLength = value
            }

            ConfigSwitch {
                buttonIcon: "calendar_view_month"
                text: Translation.tr("Force 2-char day names in Waffle calendar")
                checked: Config.options.waffles.calendar.force2CharDayOfWeek
                onCheckedChanged: Config.options.waffles.calendar.force2CharDayOfWeek = checked
            }
        }
    }

    ContentSection {
        icon: "data_object"
        title: Translation.tr("Advanced JSON-backed fields")

        ContentSubsection {
            title: Translation.tr("AI models")
            tooltip: Translation.tr("Raw JSON for model definitions and sidebar toggle layouts.")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("AI tool mode")
                text: Config.options.ai.tool
                wrapMode: TextEdit.NoWrap
                onTextChanged: Config.options.ai.tool = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("[{...}]")
                text: root.normalizedJson(Config.options.ai.extraModels)
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    const parsed = root.parseJson(text, null);
                    if (parsed !== null && Array.isArray(parsed))
                        Config.options.ai.extraModels = parsed;
                }
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("[\"network\", \"bluetooth\"]")
                text: root.normalizedJson(Config.options.waffles.actionCenter.toggles)
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    const parsed = root.parseJson(text, null);
                    if (parsed !== null && Array.isArray(parsed))
                        Config.options.waffles.actionCenter.toggles = parsed;
                }
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("[{\"size\":2,\"type\":\"network\"}]")
                text: root.normalizedJson(Config.options.sidebar.quickToggles.android.toggles)
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    const parsed = root.parseJson(text, null);
                    if (parsed !== null && Array.isArray(parsed))
                        Config.options.sidebar.quickToggles.android.toggles = parsed;
                }
            }
        }
    }
}
