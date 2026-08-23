pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root

    title: Translation.tr("Settings")
    showCenterButton: true

    property real contentPadding: 8
    property int currentPage: Persistent.states.overlay.settingsMenu.currentPage ?? 0
    property bool configPathCopied: false
    property int requestedSubTab: -1
    property string requestedSectionId: ""
    property string searchQuery: ""

    readonly property var pages: [
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

    onCurrentPageChanged: {
        Persistent.states.overlay.settingsMenu.currentPage = currentPage
        if (root.currentPage !== 0 && root.searchQuery.length > 0)
            root.searchQuery = ""
    }

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
    }

    function applyNavigation(page, subTab = -1, sectionId = "") {
        root.requestedSubTab = subTab
        root.requestedSectionId = sectionId
        const targetPage = Math.max(0, Math.min(page, root.pages.length - 1))

        if (root.currentPage === targetPage) {
            root.applyRequestedNavigationTo(pageLoader.item)
            return
        }

        root.currentPage = targetPage
    }

    function applyRequestedNavigationTo(item) {
        if (!item || root.requestedSubTab < 0 || typeof item.applySubTab !== "function")
            return

        item.applySubTab(root.requestedSubTab, root.requestedSectionId)
        root.requestedSubTab = -1
        root.requestedSectionId = ""
    }

    contentItem: Rectangle {
        id: contentRoot
        implicitWidth: 1100
        implicitHeight: 750
        radius: root.contentRadius
        color: Appearance.m3colors.m3background
        clip: true
        focus: true

        Keys.onPressed: (event) => {
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Tab) {
                    root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_Backtab) {
                    root.currentPage = Math.max(root.currentPage - 1, 0)
                    event.accepted = true
                }
            }
        }

        Timer {
            id: configPathCopyResetTimer
            interval: 1500
            onTriggered: root.configPathCopied = false
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: root.contentPadding
            spacing: root.contentPadding

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
                        expanded: contentRoot.width > 960

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

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding
                clip: true

                Item {
                    id: pageHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 64
                    z: 10

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
                            pages: root.pages
                            onQueryEdited: value => root.updateSearchQuery(value)
                            onResultSelected: result => root.applyNavigation(
                                result.pageIndex,
                                result.subTab,
                                result.sectionId
                            )
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
                    id: pageDivider
                    anchors.top: pageHeader.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.45
                }

                Loader {
                    id: pageLoader
                    anchors {
                        top: pageDivider.bottom
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    opacity: 1
                    active: Config.ready

                    Component.onCompleted: {
                        source = Quickshell.shellPath(root.pages[root.currentPage].component)
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete()
                            switchAnim.start()
                        }
                    }

                    onLoaded: {
                        if (item && "settingsHost" in item)
                            item.settingsHost = root

                        root.applyRequestedNavigationTo(item)
                    }

                    SequentialAnimation {
                        id: switchAnim

                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: 100
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                        }

                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
                                value: Quickshell.shellPath(root.pages[root.currentPage].component)
                            }
                            PropertyAction {
                                target: pageLoader
                                property: "anchors.topMargin"
                                value: 20
                            }
                        }

                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                properties: "opacity"
                                from: 0
                                to: 1
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                            }
                            NumberAnimation {
                                target: pageLoader
                                properties: "anchors.topMargin"
                                to: 0
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                            }
                        }
                    }
                }
            }
        }
    }
}
