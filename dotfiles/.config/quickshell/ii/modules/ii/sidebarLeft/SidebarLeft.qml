import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool pin: false
    property bool detach: false
    property bool extend: false
    property real sidebarWidth: root.extend ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidth
    property Item sidebarContent: null
    property var panelWindowsByScreen: ({})
    property var pinnedWindowsByScreen: ({})
    property string pinnedScreenName: ""
    property string delayedReservationClearScreenName: ""
    readonly property string targetScreenName: GlobalStates.resolvedSidebarLeftScreen()
    readonly property string attachedScreenName: root.pin
        ? (root.pinnedScreenName || root.targetScreenName)
        : root.targetScreenName
    readonly property var targetShellScreen: Quickshell.screens.find(screen => screen.name === root.targetScreenName) ?? Quickshell.screens[0] ?? null

    function registerPanelWindow(screenName, panelWindow) {
        if (!screenName)
            return;

        const nextMap = Object.assign({}, root.panelWindowsByScreen);
        nextMap[screenName] = panelWindow;
        root.panelWindowsByScreen = nextMap;
        root.relocateSidebarContent();
    }

    function unregisterPanelWindow(screenName, panelWindow) {
        if (!screenName)
            return;

        const nextMap = Object.assign({}, root.panelWindowsByScreen);
        if (nextMap[screenName] === panelWindow)
            delete nextMap[screenName];
        root.panelWindowsByScreen = nextMap;
    }

    function registerPinnedWindow(screenName, pinnedWindow) {
        if (!screenName)
            return;

        const nextMap = Object.assign({}, root.pinnedWindowsByScreen);
        nextMap[screenName] = pinnedWindow;
        root.pinnedWindowsByScreen = nextMap;
        root.relocateSidebarContent();
    }

    function unregisterPinnedWindow(screenName, pinnedWindow) {
        if (!screenName)
            return;

        const nextMap = Object.assign({}, root.pinnedWindowsByScreen);
        if (nextMap[screenName] === pinnedWindow)
            delete nextMap[screenName];
        root.pinnedWindowsByScreen = nextMap;
    }

    function pinnedContentParent() {
        return root.panelWindowsByScreen[root.pinnedScreenName]?.contentParent ?? null;
    }

    function attachedContentParent() {
        return root.pin
            ? root.pinnedContentParent()
            : (root.panelWindowsByScreen[root.attachedScreenName]?.contentParent ?? null);
    }

    function detachedContentParent() {
        return detachedSidebarWindow.contentParent ?? null;
    }

    function relocateSidebarContent() {
        if (!root.sidebarContent)
            return;

        const targetParent = root.detach
            ? root.detachedContentParent()
            : root.attachedContentParent();

        if (!targetParent) {
            Qt.callLater(root.relocateSidebarContent);
            return;
        }

        if (root.sidebarContent.parent !== targetParent)
            root.sidebarContent.parent = targetParent;
    }

    function focusSidebarContent() {
        if (root.sidebarContent?.focusActiveItem) {
            root.sidebarContent.focusActiveItem();
        } else if (root.sidebarContent?.forceActiveFocus) {
            root.sidebarContent.forceActiveFocus();
        }
    }

    function closeSidebar() {
        root.schedulePinnedReservationClear(root.pinnedScreenName);
        root.pin = false;
        root.pinnedScreenName = "";
        GlobalStates.closeSidebarLeft();
    }

    function togglePin() {
        const screenName = root.pin
            ? (root.pinnedScreenName || root.targetScreenName)
            : (root.targetScreenName || GlobalStates.resolvedSidebarLeftScreen());

        if (root.detach) {
            root.detach = false;
            GlobalStates.openSidebarLeft(screenName);
        }

        if (root.pin) {
            root.schedulePinnedReservationClear(screenName);
            root.pin = false;
            root.pinnedScreenName = "";
            GlobalStates.openSidebarLeft(screenName);
        } else {
            root.publishPinnedReservation(screenName);
            root.pinnedScreenName = screenName;
            root.pin = true;
            GlobalStates.openSidebarLeft(screenName);
        }
    }

    function pinToScreen(screenName) {
        if (!screenName)
            return;

        if (root.detach)
            root.detach = false;

        root.publishPinnedReservation(screenName);
        root.pinnedScreenName = screenName;
        root.pin = true;
        GlobalStates.openSidebarLeft(screenName);
    }

    function toggleDetach() {
        root.detach = !root.detach;
    }

    function toggleExtend() {
        root.extend = !root.extend;
    }

    function reservationWidth() {
        return root.sidebarWidth + Appearance.sizes.hyprlandGapsOut;
    }

    function publishPinnedReservation(screenName) {
        if (!screenName)
            return;

        if (reservationReleaseTimer.running && root.delayedReservationClearScreenName === screenName)
            reservationReleaseTimer.stop();
        root.delayedReservationClearScreenName = "";
        GlobalStates.setSidebarLeftPinnedReservation(screenName, root.reservationWidth());
    }

    function schedulePinnedReservationClear(screenName) {
        if (!screenName)
            return;

        root.delayedReservationClearScreenName = screenName;
        reservationReleaseTimer.restart();
    }

    function syncPinnedReservation() {
        const knownScreens = new Set([
            ...Object.keys(GlobalStates.sidebarLeftPinnedReservationByScreen ?? {}),
            root.pinnedScreenName,
            root.delayedReservationClearScreenName,
            root.targetScreenName,
        ].filter(Boolean));

        for (const screenName of knownScreens) {
            if (root.pin && GlobalStates.sidebarLeftOpen && screenName === root.pinnedScreenName) {
                root.publishPinnedReservation(screenName);
            } else if (reservationReleaseTimer.running && screenName === root.delayedReservationClearScreenName) {
                GlobalStates.setSidebarLeftPinnedReservation(screenName, root.reservationWidth());
            } else {
                GlobalStates.clearSidebarLeftPinnedReservation(screenName);
            }
        }
    }

    Timer {
        id: reservationReleaseTimer
        interval: 140
        repeat: false
        onTriggered: {
            if (root.delayedReservationClearScreenName.length > 0) {
                GlobalStates.clearSidebarLeftPinnedReservation(root.delayedReservationClearScreenName);
                root.delayedReservationClearScreenName = "";
            }
        }
    }

    Component.onCompleted: {
        root.sidebarContent = sidebarContentComponent.createObject(null, {
            "scopeRoot": root,
        });
        root.relocateSidebarContent();
        root.syncPinnedReservation();
    }

    Component.onDestruction: {
        const knownScreens = Object.keys(GlobalStates.sidebarLeftPinnedReservationByScreen ?? {});
        for (const screenName of knownScreens)
            GlobalStates.clearSidebarLeftPinnedReservation(screenName);
    }

    onDetachChanged: {
        if (root.detach) {
            root.schedulePinnedReservationClear(root.pinnedScreenName);
            root.pin = false;
            root.pinnedScreenName = "";
        }

        root.relocateSidebarContent();
        root.syncPinnedReservation();

        if (GlobalStates.sidebarLeftOpen)
            Qt.callLater(root.focusSidebarContent);
    }

    onPinChanged: {
        root.relocateSidebarContent();
        root.syncPinnedReservation();
    }
    onTargetScreenNameChanged: root.relocateSidebarContent()
    onPinnedScreenNameChanged: {
        root.relocateSidebarContent();
        root.syncPinnedReservation();
    }
    onExtendChanged: root.syncPinnedReservation()
    onSidebarWidthChanged: root.syncPinnedReservation()

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (!GlobalStates.sidebarLeftOpen && root.pin) {
                root.schedulePinnedReservationClear(root.pinnedScreenName);
                root.pin = false;
                root.pinnedScreenName = "";
            }
            root.syncPinnedReservation();
        }
    }

    Component {
        id: sidebarContentComponent
        SidebarLeftContent {
            scopeRoot: root
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property ShellScreen modelData
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            property string screenName: monitor?.name ?? modelData?.name ?? ""
            readonly property real outerGap: Appearance.sizes.hyprlandGapsOut
            readonly property real fullTopBarHeight: (!Config.options.bar.bottom && GlobalStates.barOpen)
                ? (Appearance.sizes.barHeight + Appearance.rounding.screenRounding)
                : 0
            readonly property real topBarOvershoot: (!Config.options.bar.bottom && GlobalStates.barOpen)
                ? Math.max(0, (Appearance.sizes.barHeight + Appearance.rounding.screenRounding)
                    - (Appearance.sizes.baseBarHeight
                        + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)))
                : 0
            readonly property real pinnedWindowTopGap: (!Config.options.bar.bottom && GlobalStates.barOpen)
                ? Appearance.sizes.barHeight
                : outerGap
            property bool pinnedOnThisScreen: !root.detach
                && root.pin
                && screenName === root.pinnedScreenName
            readonly property real topClearance: outerGap
            readonly property real pinnedTopClearance: 0
            readonly property real pinnedBottomClearance: outerGap
            readonly property real flyoutTopClearance: topClearance
            readonly property real flyoutBottomClearance: outerGap
            property bool flyoutOpen: !root.detach
                && !root.pin
                && GlobalStates.sidebarLeftOpen
                && screenName === GlobalStates.sidebarLeftScreen
            property bool pinnedWindowOpen: pinnedOnThisScreen
                && GlobalStates.sidebarLeftOpen

            PanelWindow {
                id: panelWindow
                screen: screenScope.modelData
                visible: true

                property var contentParent: sidebarLeftBackground

                function hide() {
                    root.closeSidebar();
                }

                function syncFocusGrab() {
                    GlobalFocusGrab.removeDismissable(panelWindow);
                    GlobalFocusGrab.removePersistent(panelWindow);

                    if (root.detach)
                        return;

                    if (screenScope.pinnedWindowOpen) {
                        GlobalFocusGrab.addPersistent(panelWindow);
                        return;
                    }

                    if (screenScope.flyoutOpen)
                        GlobalFocusGrab.addDismissable(panelWindow);
                }

                Component.onCompleted: {
                    root.registerPanelWindow(screenScope.screenName, panelWindow);
                    panelWindow.syncFocusGrab();
                }
                Component.onDestruction: {
                    GlobalFocusGrab.removeDismissable(panelWindow);
                    GlobalFocusGrab.removePersistent(panelWindow);
                    root.unregisterPanelWindow(screenScope.screenName, panelWindow);
                }

                exclusionMode: ExclusionMode.Normal
                exclusiveZone: screenScope.pinnedWindowOpen ? Math.ceil(root.sidebarWidth + screenScope.outerGap) : 0
                implicitWidth: root.sidebarWidth + screenScope.outerGap
                implicitHeight: screen?.height ?? 2160
                WlrLayershell.namespace: "quickshell:sidebarLeft"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                color: "transparent"

                anchors {
                    top: true
                    left: true
                    bottom: true
                }

                margins {
                    top: screenScope.pinnedWindowOpen ? screenScope.pinnedWindowTopGap : 0
                }

                mask: Region {
                    item: sidebarLeftBackground
                }

                Connections {
                    target: screenScope
                    function onFlyoutOpenChanged() {
                        panelWindow.syncFocusGrab();
                        if (screenScope.flyoutOpen) {
                            root.relocateSidebarContent();
                            Qt.callLater(root.focusSidebarContent);
                        }
                    }
                    function onPinnedWindowOpenChanged() {
                        panelWindow.syncFocusGrab();
                        if (screenScope.pinnedWindowOpen) {
                            root.relocateSidebarContent();
                            Qt.callLater(root.focusSidebarContent);
                        }
                    }
                }
                Connections {
                    target: root
                    function onPinChanged() {
                        panelWindow.syncFocusGrab();
                    }
                    function onDetachChanged() {
                        panelWindow.syncFocusGrab();
                    }
                }
                Connections {
                    target: GlobalFocusGrab
                    function onDismissed() {
                        if (!root.detach && !root.pin)
                            panelWindow.hide();
                    }
                }

                Shortcut {
                    sequence: "Ctrl+O"
                    context: Qt.WindowShortcut
                    enabled: screenScope.flyoutOpen || screenScope.pinnedWindowOpen
                    onActivated: root.toggleExtend()
                }

                Shortcut {
                    sequence: "Ctrl+P"
                    context: Qt.ApplicationShortcut
                    enabled: screenScope.flyoutOpen || screenScope.pinnedWindowOpen
                    onActivated: root.togglePin()
                }

                Shortcut {
                    sequence: "Ctrl+D"
                    context: Qt.WindowShortcut
                    enabled: screenScope.flyoutOpen || screenScope.pinnedWindowOpen
                    onActivated: root.toggleDetach()
                }

                StyledRectangularShadow {
                    target: sidebarLeftBackground
                    radius: sidebarLeftBackground.radius
                }

                Rectangle {
                    id: sidebarLeftBackground
                    focus: true
                    x: screenScope.pinnedWindowOpen ? screenScope.outerGap : -root.sidebarWidth
                    y: screenScope.pinnedWindowOpen ? screenScope.pinnedTopClearance : screenScope.flyoutTopClearance
                    width: root.sidebarWidth
                    height: Math.max(
                        1,
                        parent.height - y - (screenScope.pinnedWindowOpen
                            ? screenScope.pinnedBottomClearance
                            : screenScope.flyoutBottomClearance)
                    )
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

                    states: State {
                        name: "open"
                        when: screenScope.flyoutOpen || screenScope.pinnedWindowOpen
                        PropertyChanges { target: sidebarLeftBackground; x: screenScope.outerGap }
                    }
                    transitions: [
                        Transition {
                            to: "open"
                            NumberAnimation {
                                property: "x"
                                duration: 300
                                easing.type: Easing.OutCubic
                            }
                        },
                        Transition {
                            from: "open"
                            to: ""
                            NumberAnimation {
                                property: "x"
                                duration: 200
                                easing.type: Easing.InCubic
                            }
                        }
                    ]

                    Behavior on width {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onPressedChanged: {
                            if (pressed)
                                sidebarLeftBackground.forceActiveFocus();
                        }
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape)
                            panelWindow.hide();
                    }
                }
            }

        }
    }

    ApplicationWindow {
        id: detachedSidebarWindow
        visible: root.detach && GlobalStates.sidebarLeftOpen
        flags: Qt.Window | Qt.FramelessWindowHint
        color: "transparent"
        width: root.sidebarWidth
        height: Math.max(600, (root.targetShellScreen?.height ?? 900) - Appearance.sizes.barHeight - Appearance.sizes.hyprlandGapsOut * 2)
        minimumWidth: Appearance.sizes.sidebarWidth
        minimumHeight: 500
        title: "Detached Sidebar"
        property var contentParent: detachedSidebarBackground

        x: (root.targetShellScreen?.x ?? 0) + Math.round(((root.targetShellScreen?.width ?? width) - width) / 2)
        y: (root.targetShellScreen?.y ?? 0) + Math.round(((root.targetShellScreen?.height ?? height) - height) / 2)

        onVisibleChanged: {
            if (visible) {
                root.relocateSidebarContent();
                Qt.callLater(root.focusSidebarContent);
            }
        }

        Shortcut {
            sequence: "Ctrl+O"
            context: Qt.WindowShortcut
            enabled: detachedSidebarWindow.visible
            onActivated: root.toggleExtend()
        }

        Shortcut {
            sequence: "Ctrl+P"
            context: Qt.WindowShortcut
            enabled: detachedSidebarWindow.visible
            onActivated: root.togglePin()
        }

        Shortcut {
            sequence: "Ctrl+D"
            context: Qt.WindowShortcut
            enabled: detachedSidebarWindow.visible
            onActivated: root.toggleDetach()
        }

        Shortcut {
            sequence: "Escape"
            context: Qt.WindowShortcut
            enabled: detachedSidebarWindow.visible
            onActivated: GlobalStates.closeSidebarLeft()
        }

        Rectangle {
            id: detachedSidebarBackground
            anchors.fill: parent
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            radius: Appearance.rounding.normal

            StyledRectangularShadow {
                target: detachedSidebarBackground
                radius: detachedSidebarBackground.radius
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.toggleSidebarLeft();
        }

        function close(): void {
            GlobalStates.closeSidebarLeft();
        }

        function open(): void {
            GlobalStates.openSidebarLeft();
        }

        function togglePin(): void {
            root.togglePin();
        }

        function pin(): void {
            if (!root.pin)
                root.togglePin();
        }

        function unpin(): void {
            if (root.pin)
                root.togglePin();
        }

        function openOn(screenName: string): void {
            GlobalStates.openSidebarLeft(screenName);
        }

        function pinOn(screenName: string): void {
            root.pinToScreen(screenName);
        }

        function state(): string {
            return JSON.stringify({
                pin: root.pin,
                detach: root.detach,
                pinnedScreenName: root.pinnedScreenName,
                targetScreenName: root.targetScreenName,
                attachedScreenName: root.attachedScreenName,
                sidebarLeftOpen: GlobalStates.sidebarLeftOpen,
                sidebarLeftScreen: GlobalStates.sidebarLeftScreen,
            });
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: {
            GlobalStates.toggleSidebarLeft();
        }
    }

    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"

        onPressed: {
            GlobalStates.openSidebarLeft();
        }
    }

    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"

        onPressed: {
            GlobalStates.closeSidebarLeft();
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Detach left sidebar into a window/Attach it back"

        onPressed: {
            root.toggleDetach();
        }
    }
}
