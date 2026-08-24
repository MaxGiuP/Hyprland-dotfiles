import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
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
    property string pendingSearchingText: ""
    property bool pendingFocusFirstItem: false
    // Keep the launcher surface warm. Recreating the PanelWindow, app model and
    // icon delegates on every open made the drawer feel unresponsive.
    property bool panelLoaded: true
    property string targetScreenName: ""
    property bool targetScreenPrepared: false
    // Keep the prewarmed, hidden surface on a stable output. Following the
    // focused monitor here migrates the PanelWindow on every pointer crossing
    // and briefly exposes the drawer transition on the newly focused output.
    readonly property var targetScreenObject: Quickshell.screens.find(screen => screen.name === targetScreenName)
                                               ?? Quickshell.screens[0]
                                               ?? null
    readonly property int entranceDuration: 100
    readonly property int exitDuration: 210
    signal searchRequested(string text, bool focusFirst)

    function requestSearch(text, focusFirst = true) {
        overviewScope.pendingSearchingText = text;
        overviewScope.pendingFocusFirstItem = focusFirst;
        overviewScope.searchRequested(text, focusFirst);
    }

    function prepareTargetScreen(preferredScreen = "") {
        const preferred = Quickshell.screens.find(screen => screen.name === preferredScreen);
        const focusedName = HyprlandData.monitors.find(monitor => monitor.focused)?.name
                            ?? Hyprland.focusedMonitor?.name
                            ?? "";
        const focused = Quickshell.screens.find(screen => screen.name === focusedName);
        const resolved = preferred ?? focused ?? Quickshell.screens[0] ?? null;
        overviewScope.targetScreenName = resolved?.name ?? "";
        GlobalStates.overviewScreen = overviewScope.targetScreenName;
        overviewScope.targetScreenPrepared = true;
    }

    LazyLoader {
        id: overviewPanelLoader
        active: overviewScope.panelLoaded

    PanelWindow {
        id: panelWindow
        screen: overviewScope.targetScreenObject
        property string searchingText: ""
        property bool overviewContentReady: false
        property bool entranceShown: false
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        visible: overviewScope.panelLoaded

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
        Timer {
            id: overviewPrewarmTimer
            interval: 750
            running: true
            repeat: false
            onTriggered: panelWindow.overviewContentReady = true
        }
        Timer {
            id: entranceDelay
            interval: 8
            repeat: false
            onTriggered: panelWindow.entranceShown = true
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    overviewScope.targetScreenPrepared = false;
                    panelWindow.handleOverviewClosed();
                } else {
                    if (!overviewScope.targetScreenPrepared)
                        overviewScope.prepareTargetScreen(GlobalStates.overviewScreen);
                    overviewScope.targetScreenPrepared = false;
                    panelWindow.handleOverviewOpened();
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

        function handleOverviewClosed() {
            entranceDelay.stop();
            panelWindow.entranceShown = false;
            searchWidget.disableExpandAnimation();
            overviewScope.dontAutoCancelSearch = false;
            GlobalFocusGrab.dismiss();
            GlobalStates.overviewDrawerMode = false;
        }

        function handleOverviewOpened() {
            // Do not wait for the idle warm-up if the user opens immediately.
            panelWindow.overviewContentReady = true;
            panelWindow.entranceShown = false;
            entranceDelay.restart();
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

        Component.onCompleted: {
            if (GlobalStates.overviewOpen) {
                panelWindow.handleOverviewOpened();
                if (overviewScope.pendingSearchingText.length > 0)
                    overviewScope.searchRequested(overviewScope.pendingSearchingText, overviewScope.pendingFocusFirstItem);
            }
        }

        Connections {
            target: overviewScope
            function onSearchRequested(text, focusFirst) {
                panelWindow.setSearchingText(text);
                if (focusFirst)
                    searchWidget.focusFirstItem();
                overviewScope.pendingSearchingText = "";
                overviewScope.pendingFocusFirstItem = false;
            }
        }

        Column {
            id: columnLayout
            visible: true
            opacity: panelWindow.entranceShown ? 1.0 : 0.0
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            spacing: -8

            property real slideY: panelWindow.entranceShown ? 0 : -30

            Behavior on opacity {
                NumberAnimation {
                    duration: panelWindow.entranceShown ? overviewScope.entranceDuration : overviewScope.exitDuration
                    easing.type: panelWindow.entranceShown ? Easing.OutCubic : Easing.InOutQuad
                }
            }
            Behavior on slideY {
                NumberAnimation {
                    duration: panelWindow.entranceShown ? overviewScope.entranceDuration : overviewScope.exitDuration
                    easing.type: panelWindow.entranceShown ? Easing.OutCubic : Easing.InOutQuad
                }
            }

            transform: Translate { y: columnLayout.slideY }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.overviewOpen = false;
                } else if (event.key === Qt.Key_Left) {
                    if (!panelWindow.searchingText)
                        HyprlandDispatch.dispatch("workspace r-1");
                } else if (event.key === Qt.Key_Right) {
                    if (!panelWindow.searchingText)
                        HyprlandDispatch.dispatch("workspace r+1");
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
                width: item?.implicitWidth ?? 0
                height: GlobalStates.overviewDrawerMode ? 0 : (item?.implicitHeight ?? 0)
                asynchronous: true
                active: panelWindow.overviewContentReady
                    && (Config?.options.overview.enable ?? true)
                sourceComponent: OverviewWidget {
                    screen: panelWindow.screen
                    visible: GlobalStates.overviewOpen
                        && !GlobalStates.overviewDrawerMode
                        && searchWidget.displayedText == ""
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

            property real slideY: drawerActive ? 0 : height

            transform: Translate { y: drawerPanel.slideY }

            Behavior on slideY {
                NumberAnimation {
                    duration: drawerPanel.drawerActive
                        ? overviewScope.entranceDuration
                        : overviewScope.exitDuration
                    easing.type: drawerPanel.drawerActive ? Easing.OutExpo : Easing.InOutQuad
                }
            }

            DrawerAppList {
                anchors.fill: parent
                onAppLaunched: GlobalStates.overviewOpen = false
            }
        }
    }
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        overviewScope.requestSearch(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        overviewScope.requestSearch(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    function toggleSearchAfterSuperRelease() {
        if (!GlobalStates.superReleaseMightTrigger) {
            GlobalStates.superReleaseMightTrigger = true;
            return;
        }
        if (!GlobalStates.overviewOpen)
            overviewScope.prepareTargetScreen();
        GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            if (!GlobalStates.overviewOpen)
                overviewScope.prepareTargetScreen();
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function toggleOnScreen(screenName: string) {
            if (!GlobalStates.overviewOpen)
                overviewScope.prepareTargetScreen(screenName);
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            if (!GlobalStates.overviewOpen)
                overviewScope.prepareTargetScreen();
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            overviewScope.prepareTargetScreen();
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
            if (!GlobalStates.overviewOpen)
                overviewScope.prepareTargetScreen();
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
            if (!GlobalStates.overviewOpen)
                overviewScope.prepareTargetScreen();
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
            overviewScope.toggleSearchAfterSuperRelease();
        }
    }
    GlobalShortcut {
        name: "searchToggleIfTap"
        description: "Toggles search when a Super release was not interrupted"

        onPressed: {
            overviewScope.toggleSearchAfterSuperRelease();
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
