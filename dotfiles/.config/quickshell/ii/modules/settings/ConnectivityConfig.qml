import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // Called by settings.qml after the page loads (from search navigation)
    function applySubTab(subTab, sectionId) {
        tabBar.currentIndex = subTab
        navTimer.sectionId = sectionId
        navTimer.subTab = subTab
        navTimer.restart()
    }

    Timer {
        id: navTimer
        interval: 80
        property string sectionId: ""
        property int subTab: 0
        onTriggered: {
            const loader = subTab === 0 ? internetLoader : bluetoothLoader
            if (loader.status === Loader.Ready && loader.item && typeof loader.item.scrollToSection === "function")
                loader.item.scrollToSection(sectionId)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Sub-tab bar ───────────────────────────────────────────────────
        SecondaryTabBar {
            id: tabBar
            Layout.fillWidth: true
            currentIndex: swipeView.currentIndex
            onCurrentIndexChanged: swipeView.currentIndex = currentIndex

            SecondaryTabButton {
                buttonIcon: "language"
                buttonText: Translation.tr("Internet")
            }
            SecondaryTabButton {
                buttonIcon: "bluetooth"
                buttonText: Translation.tr("Bluetooth")
            }
        }

        // ── Horizontally swipeable content ───────────────────────────────
        SwipeView {
            id: swipeView
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex
            onCurrentIndexChanged: tabBar.currentIndex = currentIndex
            clip: true

            Loader {
                id: internetLoader
                active: true
                source: "InternetConfig.qml"
            }

            Loader {
                id: bluetoothLoader
                // Lazy-load bluetooth tab on first visit
                active: swipeView.currentIndex === 1 || _btLoaded
                property bool _btLoaded: false
                onStatusChanged: if (status === Loader.Ready) _btLoaded = true
                source: "BluetoothDevicesConfig.qml"
            }
        }
    }
}
