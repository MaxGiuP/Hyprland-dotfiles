import qs
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.folderlistmodel
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.modules.common.functions

Scope {
    id: root

    // ── Shared config ─────────────────────────────────────────────────────
    readonly property string desktopPath: (Quickshell.env("HOME") || "/home/linmax") + "/Desktop"
    readonly property string positionsPath: Quickshell.shellPath("desktop_positions.json")

    readonly property int iconSize: 64
    readonly property int itemW: 88
    readonly property int itemH: 108
    readonly property int gridPad: 16
    readonly property int gridGap: 8

    // ── Positions keyed by "screenName/fileName" ──────────────────────────
    property var positions: ({})
    property bool positionsReady: false

    property var _slotCounters: ({})

    FileView {
        id: positionsFile
        path: root.positionsPath
        preload: true
        onLoaded: {
            try { root.positions = JSON.parse(positionsFile.text()) } catch(e) {}
            root.positionsReady = true
        }
        onLoadFailed: root.positionsReady = true
    }

    Timer {
        id: posReadyFallback
        interval: 500; repeat: false; running: true
        onTriggered: { if (!root.positionsReady) root.positionsReady = true }
    }

    Timer {
        id: saveTimer
        interval: 400; repeat: false
        onTriggered: positionsFile.setText(JSON.stringify(root.positions))
    }

    // ── Cross-screen drag handoff ──────────────────────────────────────────
    // Hyprland drops the Wayland pointer grab when the cursor crosses a
    // layer-shell surface boundary, so the drag ends before onMoved can
    // trigger the normal transfer.  on_DragActiveChanged detects this and
    // sets a "pending transfer"; the destination screen's bgMouseArea picks
    // it up the moment the cursor arrives (via onPressed or onPositionChanged).
    property string _pendingXferName: ""
    property string _pendingXferFrom: ""
    property real   _pendingXferY:    0
    Timer {
        id: xferGraceTimer
        interval: 800; repeat: false
        onTriggered: root._pendingXferName = ""
    }

    function assignedScreen(fileName) {
        const screens = Quickshell.screens
        for (const s of screens) {
            if (root.positions[s.name + "/" + fileName] !== undefined)
                return s.name
        }
        return screens.length > 0 ? screens[0].name : ""
    }

    function savePos(screenName, fileName, x, y) {
        const p = Object.assign({}, root.positions)
        p[screenName + "/" + fileName] = { x: x, y: y }
        root.positions = p
        saveTimer.restart()
    }

    function moveToScreen(fromScreen, toScreen, fileName, newX, newY) {
        const p = Object.assign({}, root.positions)
        delete p[fromScreen + "/" + fileName]
        p[toScreen + "/" + fileName] = { x: newX, y: newY }
        root.positions = p
        saveTimer.restart()
    }

    function nextSlot(screenName) {
        const v = root._slotCounters[screenName] || 0
        root._slotCounters[screenName] = v + 1
        return v
    }

    function initialPos(screenName, fileName, screenW, screenH, topOff) {
        const key   = screenName + "/" + fileName
        const cellW = root.itemW + root.gridGap
        const cellH = root.itemH + root.gridGap
        const rows  = Math.max(1, Math.floor((screenH - topOff - root.gridPad) / cellH))
        if (root.positions[key] !== undefined) {
            const saved = root.positions[key]
            const col   = Math.max(0, Math.round((saved.x - root.gridPad) / cellW))
            const row   = Math.max(0, Math.min(rows - 1, Math.round((saved.y - topOff) / cellH)))
            const snappedX = root.gridPad + col * cellW
            const snappedY = topOff + row * cellH
            // Resolve overlap: if the snapped cell is already taken, shift to nearest free cell
            return root.findFreeCell(screenName, fileName, snappedX, snappedY, screenW, screenH, topOff)
        }
        // New item: scan the grid for the first free cell instead of using a blind slot counter
        // (slot counter always starts at 0 and overlaps existing items)
        return root.findFreeCell(screenName, fileName, root.gridPad, topOff, screenW, screenH, topOff)
    }

    function occupantKey(screenName, excludeName, targetX, targetY) {
        const halfW = (root.itemW + root.gridGap) / 2
        const halfH = (root.itemH + root.gridGap) / 2
        const prefix = screenName + "/"
        for (const key in root.positions) {
            if (!key.startsWith(prefix)) continue
            const name = key.substring(prefix.length)
            if (name === excludeName) continue
            const pos = root.positions[key]
            if (Math.abs(pos.x - targetX) < halfW && Math.abs(pos.y - targetY) < halfH) return key
        }
        return null
    }

    function findFreeCell(screenName, excludeName, preferX, preferY, screenW, screenH, topOff) {
        const cellW = root.itemW + root.gridGap
        const cellH = root.itemH + root.gridGap
        const cols  = Math.max(1, Math.floor((screenW - root.gridPad) / cellW))
        const rows  = Math.max(1, Math.floor((screenH - topOff - root.gridPad) / cellH))

        if (root.occupantKey(screenName, excludeName, preferX, preferY) === null)
            return { x: preferX, y: preferY }

        for (let col = 0; col < cols; col++) {
            for (let row = 0; row < rows; row++) {
                const cx = root.gridPad + col * cellW
                const cy = topOff + row * cellH
                if (root.occupantKey(screenName, excludeName, cx, cy) === null)
                    return { x: cx, y: cy }
            }
        }
        return { x: preferX, y: preferY }
    }

    function snapToGrid(px, py, screenW, screenH, topOff) {
        const cellW = root.itemW + root.gridGap
        const cellH = root.itemH + root.gridGap
        const col   = Math.max(0, Math.round((px - root.gridPad) / cellW))
        const row   = Math.max(0, Math.round((py - topOff) / cellH))
        return {
            x: Math.min(root.gridPad + col * cellW, screenW - root.itemW),
            y: Math.min(topOff + row * cellH, screenH - root.itemH)
        }
    }

    function filePathToUri(filePath) {
        const normalized = String(filePath ?? "")
        if (normalized.length === 0)
            return ""
        return "file://" + encodeURI(normalized)
    }

    function uriToFilePath(uri) {
        return FileUtils.trimFileProtocol(decodeURIComponent(String(uri ?? "")))
    }

    // ── Shared folder model ───────────────────────────────────────────────
    FolderListModel {
        id: folderModel
        folder: root.positionsReady ? ("file://" + root.desktopPath) : ""
        showDirs: true; showFiles: true; showHidden: false
        sortField: FolderListModel.Name
    }

    // ── One desktop window + one input overlay per screen ─────────────────
    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property ShellScreen modelData

            // ── Name / rename overlay state ────────────────────────────────
            property bool nameInputActive: false
            property string nameInputMode: "file"
            property real nameInputX: 0
            property real nameInputY: 0
            property string nameInputInitialText: ""
            property string renameTargetPath: ""
            property string renameTargetName: ""
            property bool renameTargetIsDir: false

            // ── Selection state ────────────────────────────────────────────
            property var selectedFileNames: []
            // Positions of all selected items at the moment a group drag starts.
            // Keyed by fileName.
            property var _groupStartPositions: ({})

            function toggleSelect(name) {
                const arr = [...selectedFileNames]
                const idx = arr.indexOf(name)
                if (idx !== -1) arr.splice(idx, 1)
                else arr.push(name)
                selectedFileNames = arr
            }

            function trashSelected() {
                for (const name of selectedFileNames)
                    Quickshell.execDetached(["gio", "trash", root.desktopPath + "/" + name])
                selectedFileNames = []
            }

            PanelWindow {
                id: desktopWindow

                screen: screenScope.modelData
                visible: !GlobalStates.screenLocked

                WlrLayershell.layer: WlrLayer.Bottom
                WlrLayershell.namespace: "quickshell:desktop"
                exclusionMode: ExclusionMode.Ignore

                anchors { top: true; bottom: true; left: true; right: true }
                color: "transparent"

                property bool menuVisible: false
                property real menuX: 0
                property real menuY: 0

                readonly property int dragMinY: Config.options.bar.bottom ? 0 : Appearance.sizes.barHeight
                readonly property int dragMaxY: Config.options.bar.bottom
                    ? height - root.itemH - Appearance.sizes.barHeight
                    : height - root.itemH

                // ── Background: rubber band selection + context menu ────────
                MouseArea {
                    id: bgMouseArea
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton | Qt.LeftButton
                    hoverEnabled: true   // needed for cross-screen ghost tracking
                    z: 0

                    property bool _rbDragging: false
                    property real _rbStartX: 0
                    property real _rbStartY: 0
                    property real _rbCurrentX: 0
                    property real _rbCurrentY: 0

                    // Cross-screen ghost state
                    property real _ghostX: root.gridPad
                    property real _ghostY: desktopWindow.dragMinY + root.gridPad
                    property bool _xferHeld: false  // arrived with button still held

                    function _isPendingDest() {
                        return root._pendingXferName !== "" &&
                               root._pendingXferFrom !== desktopWindow.screen.name
                    }

                    function _updateGhost(mx, my) {
                        if (!_isPendingDest()) return
                        const topOff = desktopWindow.dragMinY + root.gridPad
                        const snapped = root.snapToGrid(mx, my,
                            desktopWindow.width, desktopWindow.height, topOff)
                        const cell = root.findFreeCell(desktopWindow.screen.name, root._pendingXferName,
                            snapped.x, snapped.y,
                            desktopWindow.width, desktopWindow.height, topOff)
                        _ghostX = cell.x
                        _ghostY = cell.y
                    }

                    // Finalise a pending cross-screen transfer at the current ghost position.
                    function _tryXferReceive() {
                        if (!_isPendingDest()) return false
                        const screens = Quickshell.screens
                        const myIdx   = screens.findIndex(s => s.name === desktopWindow.screen.name)
                        const fromIdx = screens.findIndex(s => s.name === root._pendingXferFrom)
                        if (Math.abs(fromIdx - myIdx) !== 1) return false
                        root.moveToScreen(root._pendingXferFrom, desktopWindow.screen.name,
                            root._pendingXferName, _ghostX, _ghostY)
                        root._pendingXferName = ""
                        root.xferGraceTimer.stop()
                        _xferHeld = false
                        return true
                    }

                    onPressed: (mouse) => {
                        if (_isPendingDest()) {
                            // Arrived on this screen with button still held — track ghost
                            _xferHeld = true
                            _updateGhost(mouse.x, mouse.y)
                            return
                        }
                        if (mouse.button === Qt.LeftButton) {
                            _rbStartX = mouse.x; _rbStartY = mouse.y
                            _rbCurrentX = mouse.x; _rbCurrentY = mouse.y
                            _rbDragging = false
                        }
                    }
                    onPositionChanged: (mouse) => {
                        if (_xferHeld || (!pressed && _isPendingDest())) {
                            // Update ghost while holding or hovering over destination
                            _updateGhost(mouse.x, mouse.y)
                            return
                        }
                        if (!pressed || !(mouse.buttons & Qt.LeftButton)) return
                        _rbCurrentX = mouse.x; _rbCurrentY = mouse.y
                        if (!_rbDragging &&
                                (Math.abs(mouse.x - _rbStartX) > 6 || Math.abs(mouse.y - _rbStartY) > 6)) {
                            _rbDragging = true
                            if (!(mouse.modifiers & Qt.ControlModifier))
                                screenScope.selectedFileNames = []
                        }
                    }
                    onReleased: (mouse) => {
                        if (_xferHeld || (mouse.button === Qt.LeftButton && _isPendingDest())) {
                            _tryXferReceive()
                            return
                        }
                        if (mouse.button === Qt.LeftButton) {
                            if (_rbDragging) {
                                const rbX = Math.min(_rbStartX, _rbCurrentX)
                                const rbY = Math.min(_rbStartY, _rbCurrentY)
                                const rbW = Math.abs(_rbCurrentX - _rbStartX)
                                const rbH = Math.abs(_rbCurrentY - _rbStartY)
                                const newSel = []
                                const prefix = desktopWindow.screen.name + "/"
                                for (const key in root.positions) {
                                    if (!key.startsWith(prefix)) continue
                                    const name = key.substring(prefix.length)
                                    const pos = root.positions[key]
                                    if (pos.x < rbX + rbW && pos.x + root.itemW > rbX &&
                                        pos.y < rbY + rbH && pos.y + root.itemH > rbY)
                                        newSel.push(name)
                                }
                                if (mouse.modifiers & Qt.ControlModifier) {
                                    const combined = [...screenScope.selectedFileNames]
                                    for (const n of newSel)
                                        if (!combined.includes(n)) combined.push(n)
                                    screenScope.selectedFileNames = combined
                                } else {
                                    screenScope.selectedFileNames = newSel
                                }
                                // Leave _rbDragging = true so onClicked (which fires after
                                // onReleased even after a drag on a no-drag-target MouseArea)
                                // knows to skip the "clear selection" path.
                            } else {
                                _rbDragging = false
                            }
                        }
                    }
                    onClicked: (mouse) => {
                        if (_rbDragging) {
                            // Rubber-band just completed; selection was set in onReleased.
                            _rbDragging = false
                            return
                        }
                        if (mouse.button === Qt.RightButton) {
                            ctxMenu.isFileMenu = false
                            ctxMenu.selectedCount = screenScope.selectedFileNames.length
                            desktopWindow.menuX = mouse.x
                            desktopWindow.menuY = mouse.y
                            desktopWindow.menuVisible = true
                        } else {
                            screenScope.selectedFileNames = []
                            desktopWindow.menuVisible = false
                        }
                    }
                }

                // Cross-screen drag ghost — shown on the destination monitor while a
                // pending transfer is active so the user can see where the item will land.
                Rectangle {
                    visible: bgMouseArea._isPendingDest()
                    z: 20
                    x: bgMouseArea._ghostX
                    y: bgMouseArea._ghostY
                    width: root.itemW; height: root.itemH
                    radius: Appearance.rounding.normal
                    color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g,
                                   Appearance.colors.colPrimary.b, 0.25)
                    border.color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g,
                                          Appearance.colors.colPrimary.b, 0.7)
                    border.width: 1
                }

                // Rubber band visual
                Rectangle {
                    visible: bgMouseArea._rbDragging
                    z: 5
                    x: Math.min(bgMouseArea._rbStartX, bgMouseArea._rbCurrentX)
                    y: Math.min(bgMouseArea._rbStartY, bgMouseArea._rbCurrentY)
                    width:  Math.abs(bgMouseArea._rbCurrentX - bgMouseArea._rbStartX)
                    height: Math.abs(bgMouseArea._rbCurrentY - bgMouseArea._rbStartY)
                    color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g,
                                   Appearance.colors.colPrimary.b, 0.15)
                    border.color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g,
                                          Appearance.colors.colPrimary.b, 0.6)
                    border.width: 1; radius: 3
                }

                // ── Desktop icons ──────────────────────────────────────────
                Item {
                    anchors.fill: parent
                    z: 1

                    Repeater {
                        id: desktopRepeater
                        model: folderModel

                        DesktopItem {
                            property bool _positionSet: false
                            visible: _positionSet &&
                                     root.assignedScreen(modelData.fileName) === desktopWindow.screen.name

                            iconSize: root.iconSize
                            itemWidth: root.itemW
                            itemHeight: root.itemH
                            selected: screenScope.selectedFileNames.includes(modelData.fileName)
                            currentScreenName: desktopWindow.screen.name
                            dragUrls: {
                                const names = (selected && screenScope.selectedFileNames.length > 1)
                                    ? screenScope.selectedFileNames
                                    : [modelData.fileName]
                                return names
                                    .map(name => root.filePathToUri(root.desktopPath + "/" + name))
                                    .filter(uri => uri.length > 0)
                            }

                            drag.minimumX: {
                                const s = Quickshell.screens
                                return s.findIndex(sc => sc.name === desktopWindow.screen.name) > 0
                                    ? -root.itemW : 0
                            }
                            drag.maximumX: {
                                const s = Quickshell.screens
                                const idx = s.findIndex(sc => sc.name === desktopWindow.screen.name)
                                return idx < s.length - 1 ? desktopWindow.width
                                                          : desktopWindow.width - root.itemW
                            }
                            drag.minimumY: desktopWindow.dragMinY
                            drag.maximumY: desktopWindow.dragMaxY

                            Component.onCompleted: {
                                try {
                                    const isHere = root.assignedScreen(modelData.fileName) === desktopWindow.screen.name
                                    if (isHere) {
                                        const topOff = desktopWindow.dragMinY + root.gridPad
                                        const pos = root.initialPos(
                                            desktopWindow.screen.name, modelData.fileName,
                                            desktopWindow.width, desktopWindow.height, topOff)
                                        x = pos.x; y = pos.y
                                        root.savePos(desktopWindow.screen.name, modelData.fileName, pos.x, pos.y)
                                    }
                                } catch(e) {
                                    const fbTopOff = root.gridPad
                                    const fbRows = Math.max(1, Math.floor(
                                        (desktopWindow.height - fbTopOff * 2) / (root.itemH + root.gridGap)))
                                    const fbSlot = root.nextSlot(desktopWindow.screen.name + "_fb")
                                    x = root.gridPad + Math.floor(fbSlot / fbRows) * (root.itemW + root.gridGap)
                                    y = fbTopOff + (fbSlot % fbRows) * (root.itemH + root.gridGap)
                                } finally {
                                    _positionSet = true
                                }
                            }

                            property var _syncPos: root.positions[desktopWindow.screen.name + "/" + modelData.fileName]
                            on_SyncPosChanged: {
                                if (drag.active || !_positionSet || !visible || !_syncPos) return
                                if (Math.abs(x - _syncPos.x) > 2 || Math.abs(y - _syncPos.y) > 2) {
                                    x = _syncPos.x; y = _syncPos.y
                                }
                            }

                            property bool _dragActive: drag.active
                            on_DragActiveChanged: {
                                if (_dragActive) {
                                    // Drag just started — snapshot every selected item's position
                                    // so groupDragMoved / onMoved can compute deltas.
                                    if (_positionSet && visible && selected &&
                                            screenScope.selectedFileNames.length > 1) {
                                        const starts = {}
                                        for (let i = 0; i < desktopRepeater.count; i++) {
                                            const itm = desktopRepeater.itemAt(i)
                                            if (!itm || !itm.visible) continue
                                            const fn = itm.modelData?.fileName
                                            if (fn && screenScope.selectedFileNames.includes(fn))
                                                starts[fn] = { x: itm.x, y: itm.y }
                                        }
                                        screenScope._groupStartPositions = starts
                                    } else {
                                        screenScope._groupStartPositions = {}
                                    }
                                    return
                                }
                                if (!_positionSet || !visible) return
                                // x/y are still the drag-end position here — check for
                                // cross-screen intent before we snap the item back.
                                // Skip cross-screen detection for group drags; onMoved handles them.
                                const myName  = desktopWindow.screen.name
                                const isGroupDrag = selected &&
                                    screenScope.selectedFileNames.length > 1 &&
                                    !!screenScope._groupStartPositions[modelData.fileName]
                                if (!isGroupDrag) {
                                    const screens = Quickshell.screens
                                    const myIdx   = screens.findIndex(s => s.name === myName)
                                    const nearRight = x >= desktopWindow.width - root.itemW && myIdx < screens.length - 1
                                    const nearLeft  = x <= 0 && myIdx > 0
                                    if (nearRight || nearLeft) {
                                        root._pendingXferName = modelData.fileName
                                        root._pendingXferFrom = myName
                                        root._pendingXferY    = y
                                        root.xferGraceTimer.restart()
                                    }
                                }
                                const saved = root.positions[myName + "/" + modelData.fileName]
                                if (saved && (Math.abs(x - saved.x) > 2 || Math.abs(y - saved.y) > 2)) {
                                    x = saved.x; y = saved.y
                                }
                            }

                            // Real-time group drag: move every other selected item by the
                            // same (dx, dy) the leader has moved from its press position.
                            onGroupDragMoved: (dx, dy) => {
                                if (screenScope.selectedFileNames.length <= 1) return
                                for (let i = 0; i < desktopRepeater.count; i++) {
                                    const other = desktopRepeater.itemAt(i)
                                    if (!other || !other.visible) continue
                                    const fn = other.modelData?.fileName
                                    if (!fn || fn === modelData.fileName) continue
                                    if (!screenScope.selectedFileNames.includes(fn)) continue
                                    const sp = screenScope._groupStartPositions[fn]
                                    if (!sp) continue
                                    other.x = Math.max(0, Math.min(desktopWindow.width  - root.itemW, sp.x + dx))
                                    other.y = Math.max(desktopWindow.dragMinY,
                                                       Math.min(desktopWindow.dragMaxY, sp.y + dy))
                                }
                            }

                            onVisibleChanged: {
                                if (visible) {
                                    const saved = root.positions[desktopWindow.screen.name + "/" + modelData.fileName]
                                    if (saved) { x = saved.x; y = saved.y }
                                }
                            }

                            onLeftClicked: (ctrlHeld, shiftHeld) => {
                                desktopWindow.menuVisible = false
                                if (ctrlHeld || shiftHeld)
                                    screenScope.toggleSelect(modelData.fileName)
                                else
                                    screenScope.selectedFileNames = [modelData.fileName]
                            }

                            onMoved: (fileName, px, py) => {
                                const myName  = desktopWindow.screen.name
                                const screens = Quickshell.screens
                                const myIdx   = screens.findIndex(s => s.name === myName)

                                // ── Group drag: snap leader, apply same delta to all others ──
                                const isGroupDrag = selected &&
                                    screenScope.selectedFileNames.length > 1 &&
                                    !!screenScope._groupStartPositions[fileName]
                                if (isGroupDrag) {
                                    const topOff   = desktopWindow.dragMinY + root.gridPad
                                    const clampedX = Math.max(0, Math.min(desktopWindow.width - root.itemW, px))
                                    const clampedY = Math.max(desktopWindow.dragMinY, Math.min(desktopWindow.dragMaxY, py))
                                    const snapped  = root.snapToGrid(clampedX, clampedY,
                                                         desktopWindow.width, desktopWindow.height, topOff)
                                    const leaderStart = screenScope._groupStartPositions[fileName]
                                    if (leaderStart) {
                                        const sdx = snapped.x - leaderStart.x
                                        const sdy = snapped.y - leaderStart.y
                                        const p = Object.assign({}, root.positions)
                                        for (const name of screenScope.selectedFileNames) {
                                            const sp = screenScope._groupStartPositions[name]
                                            if (!sp) continue
                                            const nx = Math.max(0, Math.min(desktopWindow.width  - root.itemW, sp.x + sdx))
                                            const ny = Math.max(desktopWindow.dragMinY,
                                                                Math.min(desktopWindow.dragMaxY, sp.y + sdy))
                                            p[myName + "/" + name] = { x: nx, y: ny }
                                        }
                                        root.positions = p
                                        root.saveTimer.restart()
                                    }
                                    return
                                }

                                // ── Single-item drag (original logic) ────────────────────────
                                if (px >= desktopWindow.width - root.itemW && myIdx < screens.length - 1) {
                                    const nextScreen = screens[myIdx + 1]
                                    const clampedY = Math.max(desktopWindow.dragMinY, Math.min(desktopWindow.dragMaxY, py))
                                    const topOff   = desktopWindow.dragMinY + root.gridPad
                                    const snapped  = root.snapToGrid(0, clampedY, nextScreen.width, nextScreen.height, topOff)
                                    const cell     = root.findFreeCell(nextScreen.name, fileName, snapped.x, snapped.y, nextScreen.width, nextScreen.height, topOff)
                                    root.moveToScreen(myName, nextScreen.name, fileName, cell.x, cell.y)
                                    root._pendingXferName = ""; root.xferGraceTimer.stop()
                                } else if (px <= 0 && myIdx > 0) {
                                    const prevScreen = screens[myIdx - 1]
                                    const clampedY   = Math.max(desktopWindow.dragMinY, Math.min(desktopWindow.dragMaxY, py))
                                    const topOff     = desktopWindow.dragMinY + root.gridPad
                                    const snapped    = root.snapToGrid(prevScreen.width - root.itemW, clampedY, prevScreen.width, prevScreen.height, topOff)
                                    const cell       = root.findFreeCell(prevScreen.name, fileName, snapped.x, snapped.y, prevScreen.width, prevScreen.height, topOff)
                                    root.moveToScreen(myName, prevScreen.name, fileName, cell.x, cell.y)
                                    root._pendingXferName = ""; root.xferGraceTimer.stop()
                                } else {
                                    const topOff   = desktopWindow.dragMinY + root.gridPad
                                    const clampedX = Math.max(0, Math.min(desktopWindow.width - root.itemW, px))
                                    const clampedY = Math.max(desktopWindow.dragMinY, Math.min(desktopWindow.dragMaxY, py))
                                    const snapped  = root.snapToGrid(clampedX, clampedY, desktopWindow.width, desktopWindow.height, topOff)
                                    const takenKey = root.occupantKey(myName, fileName, snapped.x, snapped.y)
                                    if (takenKey !== null) {
                                        const p = Object.assign({}, root.positions)
                                        p[takenKey] = { x: _origX, y: _origY }
                                        p[myName + "/" + fileName] = { x: snapped.x, y: snapped.y }
                                        root.positions = p
                                        root.saveTimer.restart()
                                    } else {
                                        root.savePos(myName, fileName, snapped.x, snapped.y)
                                    }
                                }
                            }

                            onTrashRequested: urls => {
                                const filePaths = urls
                                    .map(uri => root.uriToFilePath(uri))
                                    .filter(path => path.length > 0)
                                if (filePaths.length === 0)
                                    return
                                Quickshell.execDetached(["gio", "trash", ...filePaths])
                                screenScope.selectedFileNames = []
                            }

                            onRightClicked: (mx, my, fpath, fname, fisDir) => {
                                if (!screenScope.selectedFileNames.includes(fname))
                                    screenScope.selectedFileNames = [fname]
                                ctxMenu.isFileMenu = true
                                ctxMenu.targetFilePath = fpath
                                ctxMenu.targetFileName = fname
                                ctxMenu.targetIsDir = fisDir
                                ctxMenu.selectedCount = screenScope.selectedFileNames.length
                                desktopWindow.menuX = mx
                                desktopWindow.menuY = my
                                desktopWindow.menuVisible = true
                            }
                        }
                    }
                }

                // ── Context menu ───────────────────────────────────────────
                DesktopContextMenu {
                    id: ctxMenu
                    visible: desktopWindow.menuVisible
                    z: 10
                    x: Math.min(desktopWindow.menuX, desktopWindow.width  - implicitWidth  - 8)
                    y: Math.min(desktopWindow.menuY, desktopWindow.height - implicitHeight - 8)
                    desktopFsPath: root.desktopPath

                    onRequestNameInput: (mode) => {
                        screenScope.nameInputMode = mode
                        screenScope.nameInputInitialText = ""
                        screenScope.nameInputX = desktopWindow.menuX
                        screenScope.nameInputY = desktopWindow.menuY
                        screenScope.nameInputActive = true
                    }
                    onRenameRequested: {
                        screenScope.nameInputMode = "rename"
                        screenScope.nameInputInitialText = ctxMenu.targetFileName
                        screenScope.renameTargetPath = ctxMenu.targetFilePath
                        screenScope.renameTargetName = ctxMenu.targetFileName
                        screenScope.renameTargetIsDir = ctxMenu.targetIsDir
                        screenScope.nameInputX = desktopWindow.menuX
                        screenScope.nameInputY = desktopWindow.menuY
                        screenScope.nameInputActive = true
                    }
                    onRefreshRequested: {
                        const f = folderModel.folder
                        folderModel.folder = ""
                        folderModel.folder = f
                        desktopWindow.menuVisible = false
                    }
                    onDeleteRequested: (fpath) => {
                        Quickshell.execDetached(["gio", "trash", fpath])
                        screenScope.selectedFileNames = []
                    }
                    onTrashSelectedRequested: {
                        screenScope.trashSelected()
                    }
                    onOpenSettingsRequested: {
                        Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")])
                    }
                    onCloseRequested: {
                        desktopWindow.menuVisible = false
                    }
                }
            }

            // ── Name/rename overlay on WlrLayer.Top (keyboard input works here) ──
            PanelWindow {
                id: nameInputWindow

                screen: screenScope.modelData
                visible: screenScope.nameInputActive
                color: "transparent"

                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "quickshell:desktop-nameinput"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

                anchors { top: true; bottom: true; left: true; right: true }

                onVisibleChanged: {
                    if (visible) {
                        nameInput.text = screenScope.nameInputInitialText
                        if (screenScope.nameInputMode === "rename")
                            nameInput.selectAll()
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: { screenScope.nameInputActive = false; nameInput.text = "" }
                }

                Rectangle {
                    x: Math.min(screenScope.nameInputX, nameInputWindow.width  - width  - 8)
                    y: Math.min(screenScope.nameInputY, nameInputWindow.height - height - 8)
                    width: 240
                    height: inputColumn.implicitHeight + 20
                    radius: Appearance.rounding.normal
                    color: Qt.rgba(Appearance.colors.colLayer1.r, Appearance.colors.colLayer1.g,
                                   Appearance.colors.colLayer1.b, 1.0)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Qt.rgba(0, 0, 0, 0.5)
                        shadowBlur: 0.8
                        shadowVerticalOffset: 4
                        shadowHorizontalOffset: 0
                    }

                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: {} }

                    ColumnLayout {
                        id: inputColumn
                        anchors { fill: parent; margins: 10 }
                        spacing: 8

                        Text {
                            text: screenScope.nameInputMode === "file"   ? "New file name:"   :
                                  screenScope.nameInputMode === "folder" ? "New folder name:" :
                                                                           "Rename to:"
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: 12
                        }

                        Rectangle {
                            Layout.fillWidth: true; height: 32
                            radius: Appearance.rounding.small
                            color: Qt.rgba(Appearance.colors.colLayer2.r, Appearance.colors.colLayer2.g,
                                           Appearance.colors.colLayer2.b, 1.0)
                            border.color: nameInput.activeFocus ? Appearance.colors.colPrimary : Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1

                            StyledTextInput {
                                id: nameInput
                                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                verticalAlignment: TextInput.AlignVCenter
                                font.pixelSize: 13
                                focus: screenScope.nameInputActive
                                Keys.onReturnPressed: nameInputWindow.confirmAction()
                                Keys.onEscapePressed: { screenScope.nameInputActive = false; nameInput.text = "" }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Item { Layout.fillWidth: true }

                            Rectangle {
                                width: cancelTxt.implicitWidth + 16; height: 26
                                radius: Appearance.rounding.small
                                color: cancelMA.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                                Text { id: cancelTxt; anchors.centerIn: parent; text: Translation.tr("Cancel")
                                       color: Appearance.colors.colOnLayer1; font.pixelSize: 12 }
                                MouseArea { id: cancelMA; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { screenScope.nameInputActive = false; nameInput.text = "" } }
                            }

                            Rectangle {
                                width: confirmTxt.implicitWidth + 16; height: 26
                                radius: Appearance.rounding.small
                                color: confirmMA.containsMouse
                                    ? Qt.lighter(Appearance.colors.colPrimary, 1.1)
                                    : Appearance.colors.colPrimary
                                Text { id: confirmTxt; anchors.centerIn: parent
                                       text: screenScope.nameInputMode === "rename" ? "Rename" : "Create"
                                       color: "white"; font.pixelSize: 12 }
                                MouseArea { id: confirmMA; anchors.fill: parent; hoverEnabled: true
                                    onClicked: nameInputWindow.confirmAction() }
                            }
                        }
                    }
                }

                function confirmAction() {
                    const name = nameInput.text.trim()
                    if (name.length === 0) return
                    const screenName = screenScope.modelData.name

                    if (screenScope.nameInputMode === "rename") {
                        const oldName = screenScope.renameTargetName
                        const oldPath = screenScope.renameTargetPath
                        if (name === oldName) { screenScope.nameInputActive = false; nameInput.text = ""; return }
                        // Transfer saved grid position to the new name
                        const oldKey = screenName + "/" + oldName
                        if (root.positions[oldKey] !== undefined) {
                            const p = Object.assign({}, root.positions)
                            p[screenName + "/" + name] = p[oldKey]
                            delete p[oldKey]
                            root.positions = p
                            root.saveTimer.restart()
                        }
                        // Use -T (--no-target-directory) for directories so that mv
                        // renames the folder instead of silently moving it inside an
                        // existing same-named directory.
                        const mvCmd = screenScope.renameTargetIsDir
                            ? ["mv", "-T", "--", oldPath, root.desktopPath + "/" + name]
                            : ["mv", "--", oldPath, root.desktopPath + "/" + name]
                        Quickshell.execDetached(mvCmd)
                        screenScope.selectedFileNames = screenScope.selectedFileNames.map(n => n === oldName ? name : n)
                    } else {
                        const topOff = desktopWindow.dragMinY + root.gridPad
                        const snapped = root.snapToGrid(
                            screenScope.nameInputX, screenScope.nameInputY,
                            nameInputWindow.width, nameInputWindow.height, topOff)
                        const cell = root.findFreeCell(
                            screenName, "", snapped.x, snapped.y,
                            nameInputWindow.width, nameInputWindow.height, topOff)
                        root.savePos(screenName, name, cell.x, cell.y)
                        if (screenScope.nameInputMode === "file")
                            Quickshell.execDetached(["touch", root.desktopPath + "/" + name])
                        else
                            Quickshell.execDetached(["mkdir", "-p", root.desktopPath + "/" + name])
                    }

                    screenScope.nameInputActive = false
                    nameInput.text = ""
                }
            }
        }
    }
}
