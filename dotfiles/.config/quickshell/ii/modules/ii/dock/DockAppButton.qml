import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.bar
import qs.modules.waffle.looks
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

DockButton {
    id: root
    property var appToplevel
    property var appListRoot
    property int lastFocused: -1
    readonly property real availableButtonSize: Math.max(0, height - topInset - bottomInset)
    readonly property bool showWindowDots: appToplevel.toplevels.length > 0
    property int iconSize: Math.max(26, Math.round(availableButtonSize * 0.9))
    property real countDotWidth: Math.max(8, iconSize * 0.28)
    property real countDotHeight: Math.max(3, iconSize * 0.11)
    readonly property real dotTopMargin: Math.max(2, iconSize * 0.04)
    readonly property real indicatorHeight: showWindowDots ? (dotTopMargin + countDotHeight) : 0
    readonly property real contentVisualHeight: iconSize + indicatorHeight
    readonly property real contentVerticalBias: Math.max(2, availableButtonSize * 0.04)
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true)) !== undefined

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR"
    readonly property bool isPinnedApp: appToplevel.pinned && !isSeparator
    readonly property var desktopEntry: DesktopEntries.heuristicLookup(appToplevel.appId)
    property real initialX: 0
    property real initialY: 0
    property bool didDrag: false
    readonly property bool pinDragActive: pinDragArea.drag.active
    onPinDragActiveChanged: {
        if (pinDragActive) {
            root.didDrag = true
            appListRoot.dockDragging = true
            appListRoot.draggedPinnedAppId = appToplevel.appId
            appListRoot.dropTargetPinnedAppId = ""
            appListRoot.clearPreviewState()
        }
    }
    readonly property bool separatorDropTarget: appListRoot.dockDragging && isSeparator && appListRoot.dropTargetPinnedAppId === ""
    readonly property bool buttonDropTarget: appListRoot.dockDragging && !isSeparator && appListRoot.dropTargetPinnedAppId === appToplevel.appId
    enabled: !isSeparator
    implicitWidth: isSeparator ? 1 : implicitHeight - topInset - bottomInset
    z: pinDragArea.drag.active ? 10 : 0
    scale: pinDragArea.drag.active ? 1.08 : 1
    opacity: pinDragArea.drag.active ? 0.92 : 1
    Drag.active: pinDragArea.drag.active
    Drag.source: root
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2

    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    function beginHoverPreview() {
        if (appToplevel.toplevels.length === 0) {
            return;
        }

        appListRoot.showPreviewForButton(root);
        lastFocused = appToplevel.toplevels.length - 1;
    }

    function endHoverPreview() {
        appListRoot.hidePreviewForButton(root);
    }

    function forceQuitApp() {
        const pidSet = new Set()
        for (const toplevel of appToplevel.toplevels) {
            const pid = Number(toplevel?.pid ?? toplevel?.hyprlandClient?.pid ?? -1)
            if (pid > 0)
                pidSet.add(pid)
        }

        const pids = Array.from(pidSet)
        if (pids.length > 0) {
            Quickshell.execDetached(["kill", "-KILL"].concat(pids.map(pid => `${pid}`)))
            return
        }

        for (const toplevel of appToplevel.toplevels)
            toplevel?.close()
    }

    Loader {
        active: isSeparator && TaskbarApps.apps.some(app => !app.pinned && app.appId !== "SEPARATOR")
        anchors {
            fill: parent
            topMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
            bottomMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
        }
        sourceComponent: DockSeparator {}
    }

    Loader {
        anchors.fill: parent
        active: false  // pinDragArea now handles hover for all items
        sourceComponent: MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
            onEntered: root.beginHoverPreview()
            onExited: root.endHoverPreview()
        }
    }

    MouseArea {
        id: pinDragArea
        anchors.fill: parent
        enabled: !root.isSeparator
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        drag.target: root
        drag.axis: Drag.XAxis
        drag.threshold: 8
        onEntered: root.beginHoverPreview()
        onExited: root.endHoverPreview()

        onPressed: event => {
            root.initialX = root.x
            root.initialY = root.y
            root.Drag.hotSpot.x = event.x
            root.Drag.hotSpot.y = event.y
            root.didDrag = false
        }

        onReleased: {
            const wasDragging = root.didDrag
            root.x = root.initialX
            root.y = root.initialY

            if (wasDragging) {
                if (appListRoot.draggedPinnedAppId.length > 0 && appListRoot.dropTargetPinnedAppId !== appListRoot.draggedPinnedAppId) {
                    TaskbarApps.movePinnedApp(appListRoot.draggedPinnedAppId, appListRoot.dropTargetPinnedAppId)
                }
            } else {
                root.click()
            }

            appListRoot.clearDragState()
        }

        onCanceled: {
            root.x = root.initialX
            root.y = root.initialY
            appListRoot.clearDragState()
        }
    }

    DropArea {
        anchors.fill: parent
        enabled: appListRoot.dockDragging && appListRoot.draggedPinnedAppId.length > 0 && appListRoot.draggedPinnedAppId !== appToplevel.appId && (root.isPinnedApp || root.isSeparator)
        onEntered: drag => {
            appListRoot.dropTargetPinnedAppId = root.isSeparator ? "" : appToplevel.appId
        }
        onExited: drag => {
            const currentTarget = root.isSeparator ? "" : appToplevel.appId
            if (appListRoot.dropTargetPinnedAppId === currentTarget) {
                appListRoot.dropTargetPinnedAppId = ""
            }
        }
    }

    onClicked: {
        if (appToplevel.toplevels.length === 0) {
            root.desktopEntry?.execute();
            return;
        }
        lastFocused = (lastFocused + 1) % appToplevel.toplevels.length
        appToplevel.toplevels[lastFocused].activate()
    }

    middleClickAction: () => {
        root.desktopEntry?.execute();
    }

    altAction: () => {
        if (root.isSeparator)
            return
        root.endHoverPreview()
        appListRoot.cancelPreviewImmediately()
        dockContextMenu.active = true
    }

    BarPopup {
        id: dockContextMenu
        anchorItem: root
        onActiveChanged: {
            if (active) {
                appListRoot.contextMenuButton = root
            } else if (appListRoot.contextMenuButton === root) {
                appListRoot.contextMenuButton = null
            }
        }
        padding: 0
        visualMargin: 8
        ambientShadowWidth: 2
        contentItem: ColumnLayout {
            spacing: 0

            Rectangle {
                color: Appearance.m3colors.m3surfaceContainerHigh
                radius: Looks.radius.large
                clip: true
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                implicitWidth: 220
                implicitHeight: menuColumn.implicitHeight + 16

                ColumnLayout {
                    id: menuColumn
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    DockMaterialMenuButton {
                        visible: appToplevel.toplevels.length > 0
                        label: "Force quit"
                        symbol: "close"
                        onTriggered: {
                            root.forceQuitApp()
                            dockContextMenu.close()
                        }
                    }

                    DockMaterialMenuButton {
                        label: root.isPinnedApp ? "Unpin from bar" : "Pin to bar"
                        symbol: root.isPinnedApp ? "keep_off" : "keep"
                        onTriggered: {
                            TaskbarApps.togglePin(appToplevel.appId)
                            dockContextMenu.close()
                        }
                    }
                }
            }
        }
    }

    component DockMaterialMenuButton: RippleButton {
        id: menuButton
        required property string label
        required property string symbol
        signal triggered()

        Layout.fillWidth: true
        implicitHeight: 48
        buttonRadius: 16
        colBackground: "transparent"
        colBackgroundHover: Appearance.m3colors.m3secondaryContainer
        colRipple: Qt.rgba(Appearance.m3colors.m3primary.r,
                           Appearance.m3colors.m3primary.g,
                           Appearance.m3colors.m3primary.b, 0.16)

        onClicked: triggered()

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: Qt.rgba(Appearance.m3colors.m3primary.r,
                               Appearance.m3colors.m3primary.g,
                               Appearance.m3colors.m3primary.b, 0.14)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: menuButton.symbol
                    iconSize: 17
                    color: Appearance.m3colors.m3primary
                }
            }

            Text {
                Layout.fillWidth: true
                text: menuButton.label
                color: Appearance.m3colors.m3onSurface
                font.pixelSize: 14
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    contentItem: Loader {
        active: !isSeparator
        sourceComponent: Item {
            anchors.fill: parent

            Item {
                id: visualContent
                width: root.iconSize
                height: root.contentVisualHeight
                anchors.centerIn: parent
                anchors.verticalCenterOffset: Math.round(root.indicatorHeight / 2 + root.contentVerticalBias)

                Loader {
                    id: iconImageLoader
                    width: root.iconSize
                    height: root.iconSize
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    active: !root.isSeparator
                    sourceComponent: IconImage {
                        source: Quickshell.iconPath(AppSearch.guessIcon(appToplevel.appId), "image-missing")
                        width: root.iconSize
                        height: root.iconSize
                        implicitSize: root.iconSize
                    }
                }

                Loader {
                    active: Config.options.dock.monochromeIcons
                    anchors.fill: iconImageLoader
                    sourceComponent: Item {
                        Desaturate {
                            id: desaturatedIcon
                            visible: false // There's already color overlay
                            anchors.fill: parent
                            source: iconImageLoader
                            desaturation: 0.8
                        }
                        ColorOverlay {
                            anchors.fill: desaturatedIcon
                            source: desaturatedIcon
                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                        }
                    }
                }

                Rectangle {
                    visible: buttonDropTarget
                    anchors {
                        left: parent.left
                        verticalCenter: iconImageLoader.verticalCenter
                        leftMargin: -6
                    }
                    implicitWidth: 4
                    implicitHeight: iconImageLoader.implicitHeight + 6
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary
                }

                RowLayout {
                    visible: root.showWindowDots
                    spacing: 3
                    anchors {
                        top: iconImageLoader.bottom
                        topMargin: root.dotTopMargin
                        horizontalCenter: parent.horizontalCenter
                    }
                    Repeater {
                        model: Math.min(appToplevel.toplevels.length, 3)
                        delegate: Rectangle {
                            required property int index
                            radius: Appearance.rounding.full
                            implicitWidth: (appToplevel.toplevels.length <= 3) ?
                                root.countDotWidth : root.countDotHeight
                            implicitHeight: root.countDotHeight
                            color: appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: separatorDropTarget
        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: parent.verticalCenter
        }
        implicitWidth: 4
        implicitHeight: parent.height * 0.65
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary
    }
}
