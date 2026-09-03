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
    property int pendingSubTab: -1
    property string pendingSectionId: ""

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
        root.pendingSubTab = Math.max(0, Math.min(subTab, 2))
        root.pendingSectionId = sectionId
        tabBar.currentIndex = root.pendingSubTab
        root.applyPendingNavigation()
    }

    function applyPendingNavigation() {
        if (root.pendingSubTab < 0)
            return

        const loader = root.pendingSubTab === 0
            ? internetLoader
            : root.pendingSubTab === 1 ? bluetoothLoader : sharingLoader
        if (loader.status !== Loader.Ready || !loader.item)
            return

        const item = loader.item
        const sectionId = root.pendingSectionId
        root.pendingSubTab = -1
        root.pendingSectionId = ""
        if (sectionId && typeof item.scrollToSection === "function")
            Qt.callLater(() => item.scrollToSection(sectionId))
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
                    root.applyPendingNavigation()
                }
            }

            Loader {
                id: bluetoothLoader
                // Lazy-load bluetooth tab on first visit
                active: swipeView.currentIndex === 1 || _btLoaded
                property bool _btLoaded: false
                onStatusChanged: if (status === Loader.Ready) _btLoaded = true
                source: "BluetoothDevicesConfig.qml"
                onLoaded: {
                    if (item && "settingsHost" in item)
                        item.settingsHost = root.settingsHost
                    root.applyPendingNavigation()
                }
            }

            Loader {
                id: sharingLoader
                active: swipeView.currentIndex === 2 || _sharingLoaded
                property bool _sharingLoaded: false
                onStatusChanged: if (status === Loader.Ready) _sharingLoaded = true
                source: "SharingConfig.qml"
                onLoaded: root.applyPendingNavigation()
            }
        }
    }
}
