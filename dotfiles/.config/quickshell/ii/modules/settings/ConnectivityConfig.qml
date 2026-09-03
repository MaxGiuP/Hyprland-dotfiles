import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property var settingsHost: null
    property bool pageActive: true

    function syncChildActivity() {
        if (internetLoader.item && "pageActive" in internetLoader.item)
            internetLoader.item.pageActive = root.pageActive && swipeView.currentIndex === 0
    }

    onPageActiveChanged: root.syncChildActivity()

    onSettingsHostChanged: {
        if (internetLoader.item && "settingsHost" in internetLoader.item)
            internetLoader.item.settingsHost = root.settingsHost
        if (bluetoothLoader.item && "settingsHost" in bluetoothLoader.item)
            bluetoothLoader.item.settingsHost = root.settingsHost
    }

    // Called by settings.qml after the page loads (from search navigation)
    function applySubTab(subTab, sectionId = "") {
        tabBar.currentIndex = Math.max(0, Math.min(subTab, 2))
        navTimer.sectionId = sectionId
        navTimer.subTab = tabBar.currentIndex
        navTimer.restart()
    }

    Timer {
        id: navTimer
        interval: 80
        property string sectionId: ""
        property int subTab: 0
        onTriggered: {
            const loader = subTab === 0 ? internetLoader : subTab === 1 ? bluetoothLoader : sharingLoader
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
            SecondaryTabButton {
                buttonIcon: "share"
                buttonText: Translation.tr("Sharing")
            }
        }

        // ── Horizontally swipeable content ───────────────────────────────
        SwipeView {
            id: swipeView
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex
            onCurrentIndexChanged: {
                tabBar.currentIndex = currentIndex
                root.syncChildActivity()
            }
            clip: true

            Loader {
                id: internetLoader
                active: true
                source: "InternetConfig.qml"
                onLoaded: {
                    if (item && "settingsHost" in item)
                        item.settingsHost = root.settingsHost
                    root.syncChildActivity()
                }
            }

            Loader {
                id: bluetoothLoader
                // Lazy-load bluetooth tab on first visit
                active: swipeView.currentIndex === 1 || _btLoaded
                property bool _btLoaded: false
                onStatusChanged: if (status === Loader.Ready) _btLoaded = true
                source: "BluetoothDevicesConfig.qml"
                onLoaded: if (item && "settingsHost" in item) item.settingsHost = root.settingsHost
            }

            Loader {
                id: sharingLoader
                active: swipeView.currentIndex === 2 || _sharingLoaded
                property bool _sharingLoaded: false
                onStatusChanged: if (status === Loader.Ready) _sharingLoaded = true
                source: "SharingConfig.qml"
            }
        }
    }
}
