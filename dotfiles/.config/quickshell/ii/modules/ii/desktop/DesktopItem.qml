import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs

MouseArea {
    id: root

    // Set by Repeater in Desktop.qml
    required property var modelData

    property int iconSize: 64
    property int itemWidth: 88
    property int itemHeight: 108
    property bool selected: false
    property var dragUrls: []
    property string currentScreenName: ""
    property real dragMinimumX: 0
    property real dragMaximumX: 0
    property real dragMinimumY: 0
    property real dragMaximumY: 0
    readonly property string displayLabel: {
        const raw = modelData && modelData.fileName ? String(modelData.fileName) : ""
        const name = raw.endsWith(".desktop") ? raw.slice(0, -8) : raw
        return name.replace(/(.{12})/g, "$1\n")
    }
    readonly property bool dragging: _dragActive

    signal moved(string name, real px, real py)
    signal trashRequested(var urls)
    signal leftClicked(bool ctrlHeld, bool shiftHeld)
    signal rightClicked(real mx, real my, string fpath, string fname, bool fisDir)
    // Emitted on every pixel of movement while this item is the drag leader of a group.
    // dx/dy are the displacement from the press position.
    signal groupDragMoved(real dx, real dy)
    signal dragReleaseRequested()

    width: itemWidth
    height: itemHeight

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: dragging ? Qt.ClosedHandCursor
        : containsMouse ? Qt.PointingHandCursor
        : Qt.ArrowCursor

    property bool _wasDragged: false
    property bool _dragActive: false
    property real _origX: 0
    property real _origY: 0
    property real _lastPointerX: 0
    property real _lastPointerY: 0
    property real _pressOffsetX: 0
    property real _pressOffsetY: 0

    Timer {
        id: dragClickResetTimer
        interval: 0
        repeat: false
        onTriggered: root._wasDragged = false
    }

    function dragVisualData() {
        return {
            fileName: modelData.fileName,
            filePath: modelData.filePath,
            fileIsDir: modelData.fileIsDir,
            fileUrl: modelData.fileUrl ? modelData.fileUrl : ("file://" + encodeURI(modelData.filePath || ""))
        }
    }

    function updateDragPointer(mouseX, mouseY) {
        _lastPointerX = mouseX
        _lastPointerY = mouseY
        GlobalStates.updateDesktopDragPointer(currentScreenName, x + mouseX, y + mouseY)
    }

    function releasedOverTrash() {
        const px = GlobalStates.desktopDragPointerX
        const py = GlobalStates.desktopDragPointerY
        if (px < 0 || py < 0)
            return false

        const rects = GlobalStates.desktopTrashRects ?? {}
        for (const screenName in rects) {
            const rect = rects[screenName]
            if (!rect || !rect.visible)
                continue
            if (px >= rect.x && px <= rect.x + rect.width &&
                    py >= rect.y && py <= rect.y + rect.height)
                return true
        }
        return false
    }

    function currentLocalDragPosition(mouseX, mouseY) {
        return {
            x: Math.max(dragMinimumX, Math.min(dragMaximumX, _origX + mouseX - _pressOffsetX)),
            y: Math.max(dragMinimumY, Math.min(dragMaximumY, _origY + mouseY - _pressOffsetY))
        }
    }

    function startDesktopDrag(mouseX, mouseY) {
        if (_dragActive)
            return

        _dragActive = true
        _wasDragged = true
        GlobalStates.beginDesktopDrag(
            currentScreenName,
            dragUrls.slice(),
            _pressOffsetX,
            _pressOffsetY,
            dragVisualData()
        )
        updateDragPointer(mouseX, mouseY)
    }

    onPressed: mouse => {
        _wasDragged = false
        dragClickResetTimer.stop()
        _origX = x
        _origY = y
        _pressOffsetX = mouse.x
        _pressOffsetY = mouse.y
        _lastPointerX = mouse.x
        _lastPointerY = mouse.y
    }
    onPositionChanged: mouse => {
        if (!(pressedButtons & Qt.LeftButton))
            return

        if (!_dragActive) {
            if (Math.abs(mouse.x - _pressOffsetX) <= 6 && Math.abs(mouse.y - _pressOffsetY) <= 6)
                return
            startDesktopDrag(mouse.x, mouse.y)
        }

        if (_dragActive) {
            updateDragPointer(mouse.x, mouse.y)
            const localPos = currentLocalDragPosition(mouse.x, mouse.y)
            if (selected)
                groupDragMoved(localPos.x - _origX, localPos.y - _origY)
        }
    }
    onReleased: mouse => {
        if (_dragActive) {
            // On Wayland with layer-shell, Qt fires onReleased on the source surface
            // when the compositor switches pointer focus to another monitor's surface
            // (i.e. when the cursor crosses the monitor boundary while LMB is still held).
            // This is a synthetic event — do NOT finalize the drop here or the item
            // will land on the wrong monitor.
            //
            // The actual LMB-up is reliably delivered by the GlobalShortcut
            // (bindrn , mouse:272 → quickshell:desktopDragMouseLeftRelease) regardless
            // of which surface has pointer focus.  That shortcut queries hyprctl cursorpos
            // for the live cursor position and owns all finalization via
            // finalizePendingTransferFromGlobalRelease.
            //
            // Exception: same-screen trash drops are detected here so that the
            // per-screen selectedFileNames can be cleared (finalizePendingTransferFromGlobalRelease
            // runs at root scope and can't access that state).
            const polledScreen = GlobalStates.desktopDragScreen
            if (polledScreen.length === 0 || polledScreen === currentScreenName)
                updateDragPointer(mouse.x, mouse.y)

            if (releasedOverTrash() && dragUrls.length > 0) {
                root.trashRequested(dragUrls)
                GlobalStates.clearDesktopDragState()
            }
            // All other drops are handled by the GlobalShortcut / bgMouseArea.

            _dragActive = false
            dragClickResetTimer.restart()
        }
    }
    onCanceled: {
        if (!_dragActive)
            return

        _dragActive = false
        _wasDragged = true
        dragClickResetTimer.restart()
    }

    onDoubleClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton) {
            if (modelData.filePath.endsWith(".desktop"))
                Quickshell.execDetached(["gio", "launch", modelData.filePath])
            else
                Quickshell.execDetached(["xdg-open", modelData.filePath])
        }
    }

    onClicked: (mouse) => {
        if (_wasDragged) return
        if (mouse.button === Qt.LeftButton)
            root.leftClicked(!!(mouse.modifiers & Qt.ControlModifier), !!(mouse.modifiers & Qt.ShiftModifier))
        else if (mouse.button === Qt.RightButton)
            root.rightClicked(
                root.x + mouse.x, root.y + mouse.y,
                modelData.filePath, modelData.fileName, modelData.fileIsDir
            )
    }

    // Selection + hover highlight
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: Appearance.rounding.normal
        color: root.selected
            ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b,
                      root.containsMouse ? 0.45 : 0.32)
            : Qt.rgba(1, 1, 1, root.containsMouse ? (root.dragging ? 0.22 : 0.13) : 0)
        Behavior on color { ColorAnimation { duration: 80 } }

        // Selection border
        border.width: root.selected ? 1 : 0
        border.color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.8)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4

        // Icon — reuses the existing DirectoryIcon widget which handles
        // mime detection, special folder icons, and image thumbnails
        DirectoryIcon {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.iconSize
            Layout.preferredHeight: root.iconSize
            fileModelData: root.modelData
        }

        // Label
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            text: root.displayLabel
            color: "white"
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.75)
        }
    }
}
