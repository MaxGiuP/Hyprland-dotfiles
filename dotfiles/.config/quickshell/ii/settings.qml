//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env II_SETTINGS_APP=1
//@ pragma Env II_STANDALONE_APP=1

//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    id: root

    property real contentPadding: 8
    property int currentPage: 0
    property bool configPathCopied: false
    readonly property bool showWindowHeader: Config.options?.windows?.showTitlebar ?? true
    // Sub-tab + scroll-target forwarded from search results (-1 = no pending nav)
    property int requestedSubTab: -1
    property string requestedSectionId: ""
    property string searchQuery: ""

    property var pages: [
        { displayName: Translation.tr("Home"), description: Translation.tr("Overview and shortcuts"), icon: "home", component: "modules/settings/HomeConfig.qml" },
        { displayName: Translation.tr("Connectivity"), description: Translation.tr("Wi-Fi, Ethernet and Bluetooth"), icon: "language", component: "modules/settings/ConnectivityConfig.qml" },
        { displayName: Translation.tr("Peripherals"), description: Translation.tr("Mouse, touchpad and keyboard"), icon: "mouse", component: "modules/settings/PeripheralsConfig.qml" },
        { displayName: Translation.tr("Display"), description: Translation.tr("Monitors, brightness and power"), icon: "desktop_windows", component: "modules/settings/DisplayPowerConfig.qml" },
        { displayName: Translation.tr("Audio"), description: Translation.tr("Devices, streams and volume"), icon: "volume_up", component: "modules/settings/AudioControlConfig.qml" },
        { displayName: Translation.tr("Personalisation"), description: Translation.tr("Theme, wallpaper and interface"), icon: "palette", component: "modules/settings/PersonalisationConfig.qml" },
        { displayName: Translation.tr("Account"), description: Translation.tr("Users and authentication"), icon: "person", component: "modules/settings/AccountsConfig.qml" },
        { displayName: Translation.tr("Date, time & language"), description: Translation.tr("Locale, clock and translation"), icon: "schedule", component: "modules/settings/DateTimeLanguageConfig.qml" },
        { displayName: Translation.tr("Accessibility"), description: Translation.tr("Sizing, readability and motion"), icon: "accessibility_new", component: "modules/settings/AccessibilityConfig.qml" },
        { displayName: Translation.tr("Security & privacy"), description: Translation.tr("Local data and permissions"), icon: "shield_lock", component: "modules/settings/PrivacySecurityConfig.qml" },
        { displayName: Translation.tr("System info & update"), description: Translation.tr("Hardware, software and updates"), icon: "system_update", component: "modules/settings/SystemInfoUpdateConfig.qml" },
        { displayName: Translation.tr("Services"), description: Translation.tr("Integrations and default tools"), icon: "widgets", component: "modules/settings/ServicesConfig.qml" },
        { displayName: Translation.tr("Hyprland"), description: Translation.tr("Keybinds, rules and configuration"), icon: "deployed_code", component: "modules/settings/HyprConfig.qml" }
    ]

    function copyConfigPath() {
        root.configPathCopied = true
        Quickshell.clipboardText = Directories.shellConfigPath
        configPathCopyResetTimer.restart()
    }

    function openConfigFile() {
        Quickshell.execDetached(["xdg-open", Directories.shellConfigPath])
    }

    function updateSearchQuery(query) {
        root.searchQuery = query
        if (query.trim().length > 0)
            root.currentPage = 0
    }

    onCurrentPageChanged: {
        if (root.currentPage !== 0 && root.searchQuery.length > 0)
            root.searchQuery = ""
    }

    function prepareLoadedPage(item) {
        if (item && "settingsHost" in item)
            item.settingsHost = root
    }

    function applyRequestedNavigationTo(item) {
        if (!item || root.requestedSubTab < 0 || typeof item.applySubTab !== "function")
            return

        item.applySubTab(root.requestedSubTab, root.requestedSectionId)
        root.requestedSubTab = -1
        root.requestedSectionId = ""
    }

    visible: true
    onClosing: Qt.quit()
    title: Translation.tr("illogical-impulse Settings")

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Config.readWriteDelay = 0
    }

    minimumWidth: 750
    minimumHeight: 500
    width: 1100
    height: 750
    color: Appearance.m3colors.m3background

    Timer {
        id: configPathCopyResetTimer
        interval: 1500
        onTriggered: root.configPathCopied = false
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.contentPadding
        spacing: root.contentPadding

        Keys.onPressed: (event) => {
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown) {
                    root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageUp) {
                    root.currentPage = Math.max(root.currentPage - 1, 0)
                    event.accepted = true
                } else if (event.key === Qt.Key_Tab) {
                    root.currentPage = (root.currentPage + 1) % root.pages.length
                    event.accepted = true
                } else if (event.key === Qt.Key_Backtab) {
                    root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length
                    event.accepted = true
                }
            }
        }

        // Titlebar
        Item {
            visible: root.showWindowHeader
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)

            StyledText {
                id: titleText
                anchors {
                    left: (Config.options?.windows?.centerTitle ?? true) ? undefined : parent.left
                    horizontalCenter: (Config.options?.windows?.centerTitle ?? true) ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Settings")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.disableVariableFonts ? ({}) : Appearance.font.variableAxes.title
                }
            }

            RowLayout {
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right

                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.contentPadding

            // Nav rail wrapper — width animates when collapsed/expanded
            Item {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 2
                implicitWidth: navRail.expanded ? 252 : 56

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                StyledFlickable {
                    id: navRailFlickable
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    contentHeight: navRail.implicitHeight
                    flickableDirection: Flickable.VerticalFlick

                    NavigationRail {
                        id: navRail
                        width: navRailFlickable.width
                        spacing: 2
                        expanded: root.width > 960

                        NavigationRailExpandButton {
                            focus: root.visible
                        }

                        NavigationRailTabArray {
                            currentIndex: root.currentPage
                            expanded: navRail.expanded

                            Repeater {
                                model: root.pages
                                NavigationRailButton {
                                    required property int index
                                    required property var modelData

                                    toggled: root.currentPage === index
                                    onPressed: root.currentPage = index
                                    expanded: navRail.expanded
                                    showCollapsedText: false
                                    buttonIcon: modelData.icon
                                    buttonText: modelData.displayName
                                    baseSize: 44
                                    baseHighlightHeight: 34
                                }
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }
                    }
                }
            }

            // Content pane
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 14
                            spacing: 12

                            Rectangle {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colSecondaryContainer

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.pages[root.currentPage]?.icon ?? "settings"
                                    iconSize: 21
                                    fill: 1
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.pages[root.currentPage]?.displayName ?? ""
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.pages[root.currentPage]?.description ?? ""
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    elide: Text.ElideRight
                                }
                            }

                            SettingsHeaderSearch {
                                query: root.searchQuery
                                onQueryEdited: value => root.updateSearchQuery(value)
                            }

                            IconToolbarButton {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                text: root.configPathCopied ? "check" : "code"
                                downAction: () => root.openConfigFile()
                                altAction: () => root.copyConfigPath()

                                StyledToolTip {
                                    text: Translation.tr("Open config file\nRight-click to copy path")
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Appearance.colors.colOutlineVariant
                        opacity: 0.45
                    }

                    Item {
                        id: pageStack
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Repeater {
                            model: root.pages

                            Loader {
                                required property int index
                                required property var modelData

                                property bool loadedOnce: false
                                readonly property bool current: root.currentPage === index

                                anchors.fill: parent
                                active: Config.ready && (current || loadedOnce)
                                asynchronous: !current
                                source: modelData.component
                                visible: active && (current || opacity > 0.001)
                                enabled: current
                                opacity: current && status === Loader.Ready ? 1 : 0
                                z: current ? 1 : 0

                                onLoaded: {
                                    loadedOnce = true
                                    root.prepareLoadedPage(item)
                                    applyRequestedNavigation()
                                }

                                onCurrentChanged: {
                                    if (current)
                                        applyRequestedNavigation()
                                }

                                function applyRequestedNavigation() {
                                    if (current && status === Loader.Ready)
                                        root.applyRequestedNavigationTo(item)
                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: current ? 200 : 100
                                        easing.type: current ? Appearance.animation.elementMoveEnter.type : Appearance.animation.elementMoveExit.type
                                        easing.bezierCurve: current ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
