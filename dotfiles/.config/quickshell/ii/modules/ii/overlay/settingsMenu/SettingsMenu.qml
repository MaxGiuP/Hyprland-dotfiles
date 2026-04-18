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

    readonly property var pages: [
        { displayName: Translation.tr("Home"), icon: "home", component: "modules/settings/HomeConfig.qml" },
        { displayName: Translation.tr("Connectivity"), icon: "language", component: "modules/settings/ConnectivityConfig.qml" },
        { displayName: Translation.tr("Display"), icon: "desktop_windows", component: "modules/settings/DisplayPowerConfig.qml" },
        { displayName: Translation.tr("Audio"), icon: "volume_up", component: "modules/settings/AudioControlConfig.qml" },
        { displayName: Translation.tr("Customisation"), icon: "palette", component: "modules/settings/DesktopThemeConfig.qml" },
        { displayName: Translation.tr("Interface & Apps"), icon: "preview", component: "modules/settings/InterfaceConfig.qml" },
        { displayName: Translation.tr("Account"), icon: "person", component: "modules/settings/AccountsConfig.qml" },
        { displayName: Translation.tr("Date, time & language"), icon: "schedule", component: "modules/settings/DateTimeLanguageConfig.qml" },
        { displayName: Translation.tr("Accessibility"), icon: "accessibility_new", component: "modules/settings/AccessibilityConfig.qml" },
        { displayName: Translation.tr("Security & privacy"), icon: "shield_lock", component: "modules/settings/PrivacySecurityConfig.qml" },
        { displayName: Translation.tr("System info & update"), icon: "system_update", component: "modules/settings/SystemInfoUpdateConfig.qml" },
        { displayName: Translation.tr("Services"), icon: "widgets", component: "modules/settings/ServicesConfig.qml" },
        { displayName: Translation.tr("Hyprland"), icon: "deployed_code", component: "modules/settings/HyprConfig.qml" }
    ]

    onCurrentPageChanged: Persistent.states.overlay.settingsMenu.currentPage = currentPage

    function copyConfigPath() {
        root.configPathCopied = true
        Quickshell.clipboardText = Directories.shellConfigPath
        configPathCopyResetTimer.restart()
    }

    function openConfigFile() {
        Quickshell.execDetached(["xdg-open", Directories.shellConfigPath])
    }

    function applyNavigation(page, subTab = -1, sectionId = "") {
        root.currentPage = Math.max(0, Math.min(page, root.pages.length - 1))
        root.requestedSubTab = subTab
        root.requestedSectionId = sectionId
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
                Layout.margins: 5
                implicitWidth: navRail.expanded ? 180 : fab.baseSize

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
                        spacing: 10
                        expanded: contentRoot.width > 900

                        NavigationRailExpandButton {
                            focus: root.visible
                        }

                        FloatingActionButton {
                            id: fab
                            iconText: root.configPathCopied ? "check" : "edit"
                            buttonText: root.configPathCopied ? Translation.tr("Copied") : Translation.tr("Config file")
                            expanded: navRail.expanded
                            downAction: () => root.openConfigFile()
                            altAction: () => root.copyConfigPath()

                            StyledToolTip {
                                text: Translation.tr("Open config file\nRight-click to copy path")
                            }
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
                                    buttonIcon: modelData.icon
                                    buttonText: modelData.displayName
                                    showToggledHighlight: false
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

                Loader {
                    id: pageLoader
                    anchors.fill: parent
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

                        if (root.requestedSubTab >= 0 && typeof item.applySubTab === "function") {
                            item.applySubTab(root.requestedSubTab, root.requestedSectionId)
                            root.requestedSubTab = -1
                            root.requestedSectionId = ""
                        }
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
