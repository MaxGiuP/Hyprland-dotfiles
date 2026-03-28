import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool drawerOpen: false
    property string drawerScreen: ""
    property bool overviewDrawerMode: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool desktopDragActive: false
    property var desktopDragUrls: []
    property string desktopDragScreen: ""
    property real desktopDragPointerX: -1
    property real desktopDragPointerY: -1
    property var desktopTrashRects: ({})
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false

    function resolvedDrawerScreen(preferredScreen = "") {
        return preferredScreen
            || root.drawerScreen
            || HyprlandData.monitors.find(m => m.focused)?.name
            || Hyprland.focusedMonitor?.name
            || Quickshell.screens[0]?.name
            || ""
    }

    function openDrawer(preferredScreen = "") {
        root.drawerScreen = root.resolvedDrawerScreen(preferredScreen)
        root.drawerOpen = true
    }

    function closeDrawer() {
        root.drawerOpen = false
        root.drawerScreen = ""
    }

    function toggleDrawer(preferredScreen = "") {
        const targetScreen = root.resolvedDrawerScreen(preferredScreen)
        if (root.drawerOpen && root.drawerScreen === targetScreen) {
            root.closeDrawer()
            return
        }

        root.drawerScreen = targetScreen
        root.drawerOpen = true
    }

    function toggleOverviewDrawer() {
        if (root.overviewOpen && root.overviewDrawerMode) {
            root.overviewOpen = false
        } else {
            root.overviewDrawerMode = true
            root.overviewOpen = true
        }
    }

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    property real screenZoom: 1
    onScreenZoomChanged: {
        Quickshell.execDetached(["hyprctl", "keyword", "cursor:zoom_factor", root.screenZoom.toString()]);
    }
    Behavior on screenZoom {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }

    IpcHandler {
		target: "zoom"

		function zoomIn() {
            screenZoom = Math.min(screenZoom + 0.4, 3.0)
        }

        function zoomOut() {
            screenZoom = Math.max(screenZoom - 0.4, 1)
        } 
	}
}
