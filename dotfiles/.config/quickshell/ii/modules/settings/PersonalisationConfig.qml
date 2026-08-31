import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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

            Loader {
                id: styleLoader
                active: swipeView.currentIndex === 1 || styleLoaded
                // This page is large enough to trigger runaway memory use in Qt's
                // incubating Loader path. Load it synchronously when first opened.
                asynchronous: false
                property bool styleLoaded: false
                onStatusChanged: if (status === Loader.Ready) styleLoaded = true
                source: "DesktopThemeConfig.qml"
            }
        }
    }
}
