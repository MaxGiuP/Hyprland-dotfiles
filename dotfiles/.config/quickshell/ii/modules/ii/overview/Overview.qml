import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        visible: columnLayout.opacity > 0

        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        mask: Region {
            item: !GlobalStates.overviewOpen ? null
                : GlobalStates.overviewDrawerMode ? overviewFullMask
                : columnLayout
        }

        // Background click closes the overview/drawer
        MouseArea {
            anchors.fill: parent
            enabled: GlobalStates.overviewOpen
            onClicked: GlobalStates.overviewOpen = false
        }

        Item {
            id: overviewFullMask
            x: 0; y: 0
            width: panelWindow.width
            height: panelWindow.height
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Timer {
            id: focusGrabDelay
            interval: 1
            repeat: false
            onTriggered: {
                searchWidget.focusSearchInput();
                GlobalFocusGrab.addDismissable(panelWindow);
            }
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    searchWidget.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    GlobalFocusGrab.dismiss();
                    GlobalStates.overviewDrawerMode = false;
                } else {
                    if (!overviewScope.dontAutoCancelSearch) {
                        if (searchWidget.displayedText.length > 0) {
                            searchWidget.setSearchingText(searchWidget.displayedText);
                            searchWidget.focusFirstItem();
                        } else {
                            searchWidget.cancelSearch();
                        }
                    }
                    focusGrabDelay.restart();
                }
            }
            function onOverviewDrawerModeChanged() {
                if (GlobalStates.overviewDrawerMode && searchWidget.displayedText.length > 0) {
                    searchWidget.setSearchingText("");
                }
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                GlobalStates.overviewOpen = false;
            }
        }
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight

        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        Column {
            id: columnLayout
            visible: true
            opacity: GlobalStates.overviewOpen ? 1.0 : 0.0
            scale: GlobalStates.overviewOpen ? 1.0 : 0.96
            transformOrigin: Item.Top
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            spacing: -8

            property real slideY: GlobalStates.overviewOpen ? 0 : -24

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on slideY {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            transform: Translate { y: columnLayout.slideY }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.overviewOpen = false;
                } else if (event.key === Qt.Key_Left) {
                    if (!panelWindow.searchingText)
                        Hyprland.dispatch("workspace r-1");
                } else if (event.key === Qt.Key_Right) {
                    if (!panelWindow.searchingText)
                        Hyprland.dispatch("workspace r+1");
                }
            }

            SearchWidget {
                id: searchWidget
                anchors.horizontalCenter: parent.horizontalCenter
                Synchronizer on searchingText {
                    property alias source: panelWindow.searchingText
                }
            }

            Loader {
                id: overviewLoader
                anchors.horizontalCenter: parent.horizontalCenter
                active: panelWindow.visible && (Config?.options.overview.enable ?? true)
                sourceComponent: OverviewWidget {
                    screen: panelWindow.screen
                    visible: (searchWidget.displayedText == "")
                }
            }
        }

        // ── Drawer app list (slides up below search bar when drawer mode is on) ─────
        Item {
            id: drawerPanel
            // Always rendered while overview is open so opacity/slide animations play out
            visible: panelWindow.visible

            anchors {
                top: columnLayout.bottom
                topMargin: 8
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }

            readonly property bool drawerActive: GlobalStates.overviewOpen
                                                 && GlobalStates.overviewDrawerMode
                                                 && searchWidget.displayedText == ""

            property real slideY: height

            transform: Translate { y: drawerPanel.slideY }

            onDrawerActiveChanged: {
                if (drawerActive) {
                    slideOutAnim.stop()
                    slideInAnim.start()
                } else {
                    slideInAnim.stop()
                    slideOutAnim.to = drawerPanel.height
                    slideOutAnim.start()
                }
            }

            NumberAnimation {
                id: slideInAnim
                target: drawerPanel
                property: "slideY"
                to: 0
                duration: 200
                easing.type: Easing.OutExpo
            }

            NumberAnimation {
                id: slideOutAnim
                target: drawerPanel
                property: "slideY"
                to: drawerPanel.height
                duration: 320
                easing.type: Easing.OutCubic
            }

            DrawerAppList {
                anchors.fill: parent
                onAppLaunched: GlobalStates.overviewOpen = false
            }
        }
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }
}
