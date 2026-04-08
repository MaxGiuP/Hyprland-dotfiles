import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs
import qs.services
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets

DockButton {
    id: root

    property string screenName: ""
    property bool trashDropHovered: false
    property bool _desktopTrashHeld: false
    readonly property bool desktopDragHovering: {
        const rect = GlobalStates.desktopTrashRects?.[screenName]
        if (!GlobalStates.desktopDragActive || !rect || !rect.visible)
            return false

        const px = GlobalStates.desktopDragPointerX
        const py = GlobalStates.desktopDragPointerY
        return px >= rect.x && px <= rect.x + rect.width
            && py >= rect.y && py <= rect.y + rect.height
    }
    readonly property bool draggingFiles: (trashDropArea.containsDrag && trashDropHovered) || desktopDragHovering
    readonly property bool trashHasContent: trashFilesModel.count > 0
    readonly property real availableButtonSize: Math.max(0, height - topInset - bottomInset)
    readonly property real iconSize: Math.max(24, availableButtonSize * 0.78)

    function dragUrls(drag) {
        if (drag?.source?.dragUrls && drag.source.dragUrls.length > 0) {
            return drag.source.dragUrls.map(url => String(url))
        }
        if (drag?.urls && drag.urls.length > 0) {
            return drag.urls.map(url => url.toString())
        }
        if (typeof drag?.getDataAsString === "function") {
            const uriList = drag.getDataAsString("text/uri-list") || ""
            return uriList
                .split(/\r?\n/)
                .map(line => line.trim())
                .filter(line => line.length > 0 && !line.startsWith("#"))
        }
        return []
    }

    function dropUrlsToTrash(urls) {
        const filePaths = urls
            .map(url => FileUtils.trimFileProtocol(decodeURIComponent(url)))
            .filter(path => path.length > 0)
        if (filePaths.length === 0) return

        Quickshell.execDetached(["gio", "trash", ...filePaths])
    }

    function maybeDropPendingDesktopDrag() {
        if (!_desktopTrashHeld || !desktopDragHovering)
            return

        const urls = Array.isArray(GlobalStates.desktopDragUrls) ? GlobalStates.desktopDragUrls.slice() : []
        if (urls.length === 0) {
            _desktopTrashHeld = false
            return
        }

        root.dropUrlsToTrash(urls)
        _desktopTrashHeld = false
        GlobalStates.clearDesktopDragState()
    }

    function updateDesktopDragPointer(mouseX, mouseY) {
        if (!GlobalStates.desktopDragActive || screenName.length === 0)
            return

        const pos = root.mapToItem(null, mouseX, mouseY)
        const windowHeight = root.QsWindow.window?.height ?? 0
        const screenHeight = root.QsWindow.window?.screen?.height ?? 0
        GlobalStates.updateDesktopDragPointer(screenName, pos.x, screenHeight - windowHeight + pos.y)
    }

    function updateTrashRect() {
        if (screenName.length === 0)
            return

        const monitor = HyprlandData.monitors.find(m => m.name === screenName)
        const monitorX = Number(monitor?.x ?? 0)
        const monitorY = Number(monitor?.y ?? 0)
        const pos = root.mapToItem(null, 0, 0)
        const windowHeight = root.QsWindow.window?.height ?? 0
        const screenHeight = root.QsWindow.window?.screen?.height ?? 0
        const rects = Object.assign({}, GlobalStates.desktopTrashRects ?? {})
        rects[screenName] = {
            x: monitorX + pos.x,
            y: monitorY + screenHeight - windowHeight + pos.y,
            width: root.width,
            height: root.height,
            visible: root.visible
        }
        GlobalStates.desktopTrashRects = rects
    }

    colBackground: draggingFiles ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
    colBackgroundHover: draggingFiles ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
    colRipple: draggingFiles ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active

    onClicked: {
        Quickshell.execDetached(["dolphin", "--new-window", "trash:/"])
    }

    contentItem: Item {
        anchors.fill: parent

        IconImage {
            anchors.centerIn: parent
            implicitSize: root.iconSize
            source: Quickshell.iconPath(
                (root.draggingFiles || root.trashHasContent) ? "user-trash-full" : "user-trash",
                "image-missing"
            )
        }

        Rectangle {
            visible: root.draggingFiles
            anchors.fill: parent
            anchors.margins: -4
            radius: Appearance.rounding.normal + 4
            color: "transparent"
            border.width: 2
            border.color: Appearance.colors.colPrimary
        }

    }

    onXChanged: updateTrashRect()
    onYChanged: updateTrashRect()
    onWidthChanged: updateTrashRect()
    onHeightChanged: updateTrashRect()
    onVisibleChanged: updateTrashRect()
    onScreenNameChanged: updateTrashRect()
    Component.onCompleted: updateTrashRect()
    Component.onDestruction: {
        if (screenName.length === 0)
            return
        const rects = Object.assign({}, GlobalStates.desktopTrashRects ?? {})
        delete rects[screenName]
        GlobalStates.desktopTrashRects = rects
    }

    DropArea {
        id: trashDropArea
        anchors.fill: parent

        onEntered: drag => {
            root.trashDropHovered = root.dragUrls(drag).length > 0
        }

        onExited: {
            root.trashDropHovered = false
        }

        onDropped: drag => {
            const urls = root.dragUrls(drag)
            if (urls.length > 0) {
                root.dropUrlsToTrash(urls)
                if (typeof drag.acceptProposedAction === "function") {
                    drag.acceptProposedAction()
                }
            }
            root.trashDropHovered = false
        }
    }

    MouseArea {
        id: desktopDragTracker
        anchors.fill: parent
        z: 10
        enabled: GlobalStates.desktopDragActive
        visible: enabled
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        preventStealing: false
        propagateComposedEvents: true

        onPositionChanged: mouse => {
            root.updateDesktopDragPointer(mouse.x, mouse.y)
            root._desktopTrashHeld = !!(mouse.buttons & Qt.LeftButton) || !!(pressedButtons & Qt.LeftButton)
        }

        onContainsMouseChanged: {
            if (containsMouse)
                root.updateDesktopDragPointer(mouseX, mouseY)
            else
                root._desktopTrashHeld = false
        }

        onPressedButtonsChanged: {
            const leftHeld = !!(pressedButtons & Qt.LeftButton)
            if (leftHeld && containsMouse && root.desktopDragHovering) {
                root._desktopTrashHeld = true
                return
            }

            if (!leftHeld) {
                root.maybeDropPendingDesktopDrag()
                root._desktopTrashHeld = false
            }
        }
    }

    FolderListModel {
        id: trashFilesModel
        folder: "file:///home/linmax/.local/share/Trash/files"
        showDirs: true
        showFiles: true
        showDotAndDotDot: false
        showHidden: true
        sortField: FolderListModel.Unsorted
    }
}
