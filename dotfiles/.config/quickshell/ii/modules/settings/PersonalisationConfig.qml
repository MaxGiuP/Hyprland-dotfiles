import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    function applySubTab(subTab, sectionId) {
        tabBar.currentIndex = Math.max(0, Math.min(subTab, 1))
        navTimer.sectionId = sectionId
        navTimer.subTab = tabBar.currentIndex
        navTimer.retries = 0
        navTimer.restart()
    }

    Timer {
        id: navTimer
        interval: 80
        property string sectionId: ""
        property int subTab: 0
        property int retries: 0
        onTriggered: {
            const loader = subTab === 0 ? interfaceLoader : styleLoader
            if (loader.status === Loader.Ready && loader.item && typeof loader.item.scrollToSection === "function") {
                loader.item.scrollToSection(sectionId)
            } else if (sectionId.length > 0 && retries < 20) {
                retries += 1
                restart()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        SecondaryTabBar {
            id: tabBar
            Layout.fillWidth: true
            currentIndex: swipeView.currentIndex
            onCurrentIndexChanged: swipeView.currentIndex = currentIndex

            SecondaryTabButton {
                buttonIcon: "preview"
                buttonText: Translation.tr("Interface & Apps")
            }

            SecondaryTabButton {
                buttonIcon: "palette"
                buttonText: Translation.tr("Customisation")
            }
        }

        SwipeView {
            id: swipeView
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex
            onCurrentIndexChanged: tabBar.currentIndex = currentIndex
            clip: true

            Loader {
                id: interfaceLoader
                active: true
                source: "InterfaceConfig.qml"
            }

            Item {
                Loader {
                    id: styleLoader
                    anchors.fill: parent
                    active: true
                    property bool finishSynchronously: false
                    asynchronous: !finishSynchronously
                    source: "DesktopThemeConfig.qml"
                }

                Timer {
                    interval: 1500
                    running: styleLoader.status === Loader.Loading && !styleLoader.finishSynchronously
                    onTriggered: styleLoader.finishSynchronously = true
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 14
                    visible: styleLoader.status === Loader.Null || styleLoader.status === Loader.Loading

                    MaterialLoadingIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        loading: parent.visible
                        implicitSize: 52
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Loading customisation settings")
                        color: Appearance.colors.colSubtext
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 14
                    visible: styleLoader.status === Loader.Error

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "error"
                        iconSize: 42
                        color: Appearance.colors.colError
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Customisation settings failed to load")
                        color: Appearance.colors.colSubtext
                    }

                    RippleButtonWithIcon {
                        Layout.alignment: Qt.AlignHCenter
                        materialIcon: "refresh"
                        mainText: Translation.tr("Try again")
                        onClicked: {
                            styleLoader.finishSynchronously = false
                            styleLoader.source = ""
                            Qt.callLater(() => styleLoader.source = "DesktopThemeConfig.qml")
                        }
                    }
                }
            }
        }
    }
}
