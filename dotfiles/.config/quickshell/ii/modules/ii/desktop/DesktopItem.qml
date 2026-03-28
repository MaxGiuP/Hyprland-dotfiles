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
    readonly property string dragUriList: dragUrls.join("\r\n")
    readonly property string displayLabel: {
        const raw = modelData && modelData.fileName ? String(modelData.fileName) : ""
        return raw.replace(/(.{12})/g, "$1\n")
    }

    signal moved(string name, real px, real py)
    signal trashRequested(var urls)
    signal leftClicked(bool ctrlHeld, bool shiftHeld)
    signal rightClicked(real mx, real my, string fpath, string fname, bool fisDir)
    // Emitted on every pixel of movement while this item is the drag leader of a group.
    // dx/dy are the displacement from the press position.
    signal groupDragMoved(real dx, real dy)

    width: itemWidth
    height: itemHeight

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    drag.target: root
    drag.minimumX: 0
    drag.minimumY: 0
    cursorShape: drag.active ? Qt.ClosedHandCursor
        : containsMouse ? Qt.PointingHandCursor
        : Qt.ArrowCursor
    Drag.active: drag.active
    Drag.source: root
    Drag.dragType: Drag.Internal
    Drag.mimeData: ({ "text/uri-list": dragUriList })

    property bool _wasDragged: false
    property real _origX: 0
    property real _origY: 0
    property real _lastPointerX: 0
    property real _lastPointerY: 0

    function updateDragPointer(mouseX, mouseY) {
        _lastPointerX = mouseX
        _lastPointerY = mouseY
        GlobalStates.desktopDragScreen = currentScreenName
        GlobalStates.desktopDragPointerX = x + mouseX
        GlobalStates.desktopDragPointerY = y + mouseY
    }

    function releasedOverTrash() {
        const rect = GlobalStates.desktopTrashRects?.[currentScreenName]
        if (!rect || !rect.visible)
            return false

        const px = x + _lastPointerX
        const py = y + _lastPointerY
        return px >= rect.x && px <= rect.x + rect.width
            && py >= rect.y && py <= rect.y + rect.height
    }

    function clearDesktopDragBridge() {
        if (!GlobalStates.desktopDragActive && GlobalStates.desktopDragScreen === "" &&
                GlobalStates.desktopDragPointerX < 0 && GlobalStates.desktopDragPointerY < 0)
            return

        GlobalStates.desktopDragActive = false
        GlobalStates.desktopDragUrls = []
        GlobalStates.desktopDragScreen = ""
        GlobalStates.desktopDragPointerX = -1
        GlobalStates.desktopDragPointerY = -1
    }

    onPressed: mouse => {
        _wasDragged = false
        _origX = x
        _origY = y
        updateDragPointer(mouse.x, mouse.y)
    }
    onPositionChanged: mouse => {
        if (drag.active) {
            _wasDragged = true
            updateDragPointer(mouse.x, mouse.y)
        }
    }
    onXChanged: if (drag.active && selected) groupDragMoved(x - _origX, y - _origY)
    onYChanged: if (drag.active && selected) groupDragMoved(x - _origX, y - _origY)
    onReleased: {
        if (_wasDragged) {
            if (releasedOverTrash() && dragUrls.length > 0) {
                root.trashRequested(dragUrls)
                _wasDragged = false
                clearDesktopDragBridge()
                return
            }
            root.moved(modelData.fileName, root.x, root.y)
            _wasDragged = false
        }
        clearDesktopDragBridge()
    }
    onCanceled: clearDesktopDragBridge()

    onDoubleClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton)
            Quickshell.execDetached(["xdg-open", modelData.filePath])
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

    property bool _dragActiveBridge: drag.active
    on_DragActiveBridgeChanged: {
        if (_dragActiveBridge) {
            GlobalStates.desktopDragActive = true
            GlobalStates.desktopDragUrls = dragUrls.slice()
        } else if (GlobalStates.desktopDragActive) {
            clearDesktopDragBridge()
        }
    }

    // Selection + hover highlight
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: Appearance.rounding.normal
        color: root.selected
            ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b,
                      root.containsMouse ? 0.45 : 0.32)
            : Qt.rgba(1, 1, 1, root.containsMouse ? (root.drag.active ? 0.22 : 0.13) : 0)
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
