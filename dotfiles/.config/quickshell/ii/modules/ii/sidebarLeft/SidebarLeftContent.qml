import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool aiEnabled: (Config.options?.policies?.ai ?? 1) !== 0
    property bool translatorEnabled: Config.options?.sidebar?.translator?.enable ?? false
    property var tabButtonList: [
        ...(root.aiEnabled ? [{"id": "ai", "icon": "hub", "name": "", "title": Translation.tr("AI")}] : []),
        ...(root.translatorEnabled ? [{"id": "translator", "icon": "translate", "name": "", "title": Translation.tr("Translator")}] : []),
        {"id": "calculator", "icon": "calculate", "name": "", "title": Translation.tr("Calculator")},
        {"id": "kde-connect", "icon": "smartphone", "name": "", "title": Translation.tr("KDE Connect")},
    ]
    property var tabPageComponents: [
        ...(root.aiEnabled ? [aiHarness] : []),
        ...(root.translatorEnabled ? [translator] : []),
        calculatorTab,
        kdeConnectTab,
        ...(root.tabButtonList.length === 0 ? [placeholder] : []),
    ]
    property int tabCount: tabPageComponents.length
    property bool tabStateRestored: false

    function restorePersistedTab() {
        if (root.tabButtonList.length === 0)
            return;

        // A newly-created SwipeView briefly selects index 0. Do not let that
        // initialization overwrite the tab saved before the sidebar closed.
        root.tabStateRestored = false;
        const savedTabId = Persistent.states.sidebar.leftTab;
        const savedIndex = root.tabButtonList.findIndex(tab => tab.id === savedTabId);
        tabBar.setCurrentIndex(savedIndex >= 0 ? savedIndex : 0);
        root.tabStateRestored = true;
        root.persistTab(tabBar.currentIndex);
    }

    function persistTab(index) {
        if (!root.tabStateRestored || !Persistent.ready
                || index < 0 || index >= root.tabButtonList.length)
            return;

        Persistent.states.sidebar.leftTab = root.tabButtonList[index].id;
    }

    function focusActiveItem() {
        const currentPage = swipeView.currentItem;
        const target = currentPage?.loadedItem ?? currentPage;
        if (target?.focusActiveItem) {
            target.focusActiveItem();
        } else if (target?.forceActiveFocus) {
            target.forceActiveFocus();
        }
    }

    Component.onCompleted: Qt.callLater(root.restorePersistedTab)
    onTabButtonListChanged: Qt.callLater(root.restorePersistedTab)

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready)
                root.restorePersistedTab();
        }
    }

    Connections {
        target: Persistent.states.sidebar
        function onLeftTabChanged() {
            if (Persistent.ready)
                root.restorePersistedTab();
        }
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: sidebarPadding

        Toolbar {
            visible: tabButtonList.length > 0
            Layout.alignment: Qt.AlignHCenter
            enableShadow: false
            ToolbarTabBar {
                id: tabBar
                Layout.alignment: Qt.AlignHCenter
                tabButtonList: root.tabButtonList
                Synchronizer on currentIndex {
                    property alias source: swipeView.currentIndex
                }
                delegate: ToolbarTabButton {
                    required property int index
                    required property var modelData
                    current: index == tabBar.currentIndex
                    text: modelData.name
                    materialSymbol: modelData.icon
                    horizontalPadding: 7
                    onClicked: {
                        tabBar.setCurrentIndex(index);
                        root.focusActiveItem();
                    }
                    StyledToolTip {
                        text: modelData.title
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: 10
                currentIndex: tabBar.currentIndex
                onCurrentIndexChanged: root.persistTab(currentIndex)

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                Repeater {
                    model: root.tabPageComponents
                    delegate: SidebarLeftPageHost {
                        required property var modelData
                        pageComponent: modelData
                    }
                }
            }
        }

        component SidebarLeftPageHost: Item {
            id: pageHost
            required property int index
            required property Component pageComponent
            readonly property var loadedItem: pageLoader.item
            readonly property bool current: SwipeView.view?.currentIndex === index
            property bool activated: current
            width: SwipeView.view ? SwipeView.view.width : 0
            height: SwipeView.view ? SwipeView.view.height : 0

            onCurrentChanged: {
                if (current)
                    activated = true;
            }

            Loader {
                id: pageLoader
                anchors.fill: parent
                active: pageHost.activated
                visible: pageHost.current
                asynchronous: true
                sourceComponent: pageHost.pageComponent
                onLoaded: if (pageHost.current) Qt.callLater(root.focusActiveItem)
            }
        }

        Component {
            id: aiHarness
            AiHarness {}
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: consoleTab
            ShellConsole {}
        }
        Component {
            id: kdeConnectTab
            KdeConnect {}
        }
        Component {
            id: calculatorTab
            Calculator {}
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    MaterialSymbol {
        visible: root.scopeRoot?.pin ?? false
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: root.sidebarPadding + 4
            topMargin: root.sidebarPadding + 4
        }
        z: 10
        text: "keep"
        iconSize: Appearance.font.pixelSize.large
        color: Appearance.colors.colPrimary
    }
}
