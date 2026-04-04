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
    property string sidebarRightScreen: ""
    property string sidebarLeftScreen: ""
    property bool overviewDrawerMode: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property real screenLockBlurProgress: 0
    property bool screenLockHideBar: false
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
    property var barTopClearanceByScreen: ({})

    function setBarTopClearance(screenName, clearance) {
        if (!screenName)
            return

        const nextMap = Object.assign({}, root.barTopClearanceByScreen)
        nextMap[screenName] = clearance
        root.barTopClearanceByScreen = nextMap
    }

    function clearBarTopClearance(screenName) {
        if (!screenName)
            return

        const nextMap = Object.assign({}, root.barTopClearanceByScreen)
        delete nextMap[screenName]
        root.barTopClearanceByScreen = nextMap
    }

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

    function resolvedSidebarLeftScreen(preferredScreen = "") {
        return preferredScreen
            || root.sidebarLeftScreen
            || HyprlandData.monitors.find(m => m.focused)?.name
            || Hyprland.focusedMonitor?.name
            || Quickshell.screens[0]?.name
            || ""
    }

    function openSidebarLeft(preferredScreen = "") {
        root.sidebarLeftScreen = root.resolvedSidebarLeftScreen(preferredScreen)
        root.sidebarLeftOpen = true
    }

    function closeSidebarLeft() {
        root.sidebarLeftOpen = false
        root.sidebarLeftScreen = ""
    }

    function toggleSidebarLeft(preferredScreen = "") {
        const targetScreen = root.resolvedSidebarLeftScreen(preferredScreen)
        if (root.sidebarLeftOpen && root.sidebarLeftScreen === targetScreen) {
            root.closeSidebarLeft()
            return
        }

        root.sidebarLeftScreen = targetScreen
        root.sidebarLeftOpen = true
    }

    function resolvedSidebarRightScreen(preferredScreen = "") {
        return preferredScreen
            || root.sidebarRightScreen
            || HyprlandData.monitors.find(m => m.focused)?.name
            || Hyprland.focusedMonitor?.name
            || Quickshell.screens[0]?.name
            || ""
    }

    function openSidebarRight(preferredScreen = "") {
        root.sidebarRightScreen = root.resolvedSidebarRightScreen(preferredScreen)
        root.sidebarRightOpen = true
    }

    function closeSidebarRight() {
        root.sidebarRightOpen = false
        root.sidebarRightScreen = ""
    }

    function toggleSidebarRight(preferredScreen = "") {
        const targetScreen = root.resolvedSidebarRightScreen(preferredScreen)
        if (root.sidebarRightOpen && root.sidebarRightScreen === targetScreen) {
            root.closeSidebarRight()
            return
        }

        root.sidebarRightScreen = targetScreen
        root.sidebarRightOpen = true
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
        if (sidebarRightOpen) {
            if (!sidebarRightScreen)
                sidebarRightScreen = resolvedSidebarRightScreen()
            Notifications.timeoutAll();
            Notifications.markAllRead();
        } else {
            sidebarRightScreen = ""
        }
    }

    onSidebarLeftOpenChanged: {
        if (sidebarLeftOpen) {
            if (!sidebarLeftScreen)
                sidebarLeftScreen = resolvedSidebarLeftScreen()
        } else {
            sidebarLeftScreen = ""
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
