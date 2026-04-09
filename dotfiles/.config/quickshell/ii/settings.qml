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
    property var pages: [
        { displayName: Translation.tr("Home"), icon: "home", component: "modules/settings/HomeConfig.qml" },
        { displayName: Translation.tr("Quick config"), icon: "tune", component: "modules/settings/QuickConfig.qml" },
        { displayName: Translation.tr("Bluetooth & devices"), icon: "bluetooth", component: "modules/settings/BluetoothDevicesConfig.qml" },
        { displayName: Translation.tr("Display"), icon: "desktop_windows", component: "modules/settings/DisplayPowerConfig.qml" },
        { displayName: Translation.tr("Audio"), icon: "volume_up", component: "modules/settings/AudioControlConfig.qml" },
        { displayName: Translation.tr("Internet"), icon: "language", component: "modules/settings/InternetConfig.qml" },
        { displayName: Translation.tr("Customisation"), icon: "palette", component: "modules/settings/DesktopThemeConfig.qml" },
        { displayName: Translation.tr("Interface"), icon: "preview", component: "modules/settings/InterfaceConfig.qml" },
        { displayName: Translation.tr("Apps"), icon: "apps", component: "modules/settings/AppsHubConfig.qml" },
        { displayName: Translation.tr("Account"), icon: "person", component: "modules/settings/AccountsConfig.qml" },
        { displayName: Translation.tr("Date, time & language"), icon: "schedule", component: "modules/settings/DateTimeLanguageConfig.qml" },
        { displayName: Translation.tr("Accessibility"), icon: "accessibility_new", component: "modules/settings/AccessibilityConfig.qml" },
        { displayName: Translation.tr("Security & privacy"), icon: "shield_lock", component: "modules/settings/PrivacySecurityConfig.qml" },
        { displayName: Translation.tr("System info & update"), icon: "system_update", component: "modules/settings/SystemInfoUpdateConfig.qml" },
        { displayName: Translation.tr("Services"), icon: "widgets", component: "modules/settings/ServicesConfig.qml" },
        { displayName: Translation.tr("Hyprland"), icon: "deployed_code", component: "modules/settings/HyprConfig.qml" }
    ]

    function copyConfigPath() {
        root.configPathCopied = true
        Quickshell.clipboardText = Directories.shellConfigPath
        configPathCopyResetTimer.restart()
    }

    function openConfigFile() {
        Quickshell.execDetached(["xdg-open", Directories.shellConfigPath])
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
                        expanded: root.width > 900

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

            // Content pane
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding
                clip: true

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    opacity: 1.0
                    active: Config.ready

                    Component.onCompleted: {
                        source = root.pages[0].component
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete()
                            switchAnim.start()
                        }
                    }

                    SequentialAnimation {
                        id: switchAnim

                        // Fade out current page
                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: 100
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                        }
                        // Swap content and push position down (will slide up during enter)
                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
                                value: root.pages[root.currentPage].component
                            }
                            PropertyAction {
                                target: pageLoader
                                property: "anchors.topMargin"
                                value: 20
                            }
                        }
                        // Fade in + slide up
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
