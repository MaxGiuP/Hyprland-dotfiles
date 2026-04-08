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
    property real desktopDragHotspotX: 0
    property real desktopDragHotspotY: 0
    property var desktopDragVisual: null
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

    function beginDesktopDrag(screenName, urls, hotspotX, hotspotY, visual) {
        root.desktopDragActive = true
        root.desktopDragUrls = Array.isArray(urls) ? urls.slice() : []
        root.desktopDragScreen = screenName || ""
        root.desktopDragHotspotX = Number(hotspotX ?? 0)
        root.desktopDragHotspotY = Number(hotspotY ?? 0)
        root.desktopDragVisual = visual ?? null
    }

    function monitorForGlobalPoint(globalX, globalY) {
        const gx = Number(globalX ?? -1)
        const gy = Number(globalY ?? -1)
        return HyprlandData.monitors.find(m => {
            const mx = Number(m?.x ?? 0)
            const my = Number(m?.y ?? 0)
            const mw = Number(m?.width ?? 0)
            const mh = Number(m?.height ?? 0)
            return gx >= mx && gx < mx + mw && gy >= my && gy < my + mh
        }) ?? null
    }

    function screenNameForGlobalPoint(globalX, globalY) {
        return root.monitorForGlobalPoint(globalX, globalY)?.name ?? ""
    }

    function updateDesktopDragPointerGlobal(globalX, globalY) {
        root.desktopDragPointerX = Number(globalX ?? -1)
        root.desktopDragPointerY = Number(globalY ?? -1)
        const pointerScreen = root.screenNameForGlobalPoint(globalX, globalY)
        if (pointerScreen.length > 0)
            root.desktopDragScreen = pointerScreen
    }

    function updateDesktopDragPointer(screenName, localX, localY) {
        const monitor = HyprlandData.monitors.find(m => m.name === screenName)
        const monitorX = Number(monitor?.x ?? 0)
        const monitorY = Number(monitor?.y ?? 0)
        if (screenName)
            root.desktopDragScreen = screenName
        root.updateDesktopDragPointerGlobal(
            monitorX + Number(localX ?? -1),
            monitorY + Number(localY ?? -1)
        )
    }

    function clearDesktopDragState() {
        root.desktopDragActive = false
        root.desktopDragUrls = []
        root.desktopDragScreen = ""
        root.desktopDragPointerX = -1
        root.desktopDragPointerY = -1
        root.desktopDragHotspotX = 0
        root.desktopDragHotspotY = 0
        root.desktopDragVisual = null
    }

    Timer {
        id: desktopDragCursorPollTimer
        interval: 20
        repeat: true
        running: root.desktopDragActive
        onTriggered: {
            if (!desktopDragCursorProcess.running)
                desktopDragCursorProcess.running = true
        }
    }

    Process {
        id: desktopDragCursorProcess
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            id: desktopDragCursorCollector
            onStreamFinished: {
                if (!root.desktopDragActive)
                    return

                try {
                    const cursor = JSON.parse(desktopDragCursorCollector.text)
                    root.updateDesktopDragPointerGlobal(cursor?.x, cursor?.y)
                } catch (e) {
                }
            }
        }
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
