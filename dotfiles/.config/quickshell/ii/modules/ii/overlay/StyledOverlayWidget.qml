pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt5Compat.GraphicalEffects
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas

/*
 * To make an overlay widget:
 * 1. Create a modules/overlay/<yourWidget>/<YourWidget>.qml, using this as the base class and declare your widget content as contentItem
 * 2. Add an entry to OverlayContext.availableWidgets with identifier=<yourWidgetIdentifier>
 * 3. Add an entry in Persistent.states.overlay.<yourWidgetIdentifier> with x, y, width, height, pinned, clickthrough properties set to reasonable defaults
 * 4. Add an entry in OverlayWidgetDelegateChooser with roleValue=<yourWidgetIdentifier> and Declare your widget in there
 * Use existing entries as reference.
 */
AbstractOverlayWidget {
    id: root

    // To be defined by subclasses
    required property Item contentItem
    property bool fancyBorders: true
    property bool showCenterButton: false
    property bool showClickabilityButton: true
    property bool useOpacityMaskLayer: true

    // Defaults n stuff
    required property var modelData
    readonly property string identifier: (modelData && modelData.identifier) ? modelData.identifier : ""
    readonly property string materialSymbol: (modelData && modelData.materialSymbol) ? modelData.materialSymbol : "widgets"
    property string title: identifier.length > 0 ? identifier.replace(/([A-Z])/g, " $1").replace(/^./, function(str){ return str.toUpperCase(); }) : ""
    property var persistentStateEntry: (Persistent.ready && identifier.length > 0 && Persistent.states.overlay[identifier]) ? Persistent.states.overlay[identifier] : fallbackPersistentStateEntry
    property real radius: Appearance.rounding.windowRounding
    property real minimumWidth: contentItem.implicitWidth
    property real minimumHeight: contentItem.implicitHeight
    property real resizeMargin: 8
    property real padding: 6
    property real contentRadius: radius - padding
    readonly property bool showTitleBar: GlobalStates.overlayOpen
    readonly property real effectiveTitleBarHeight: showTitleBar ? (titleBarRow.implicitHeight + root.padding * 2) : 0
    readonly property string screenName: root.QsWindow.window?.screen?.name ?? "Unknown-1"
    readonly property real screenWidth: (root.parent?.width ?? 0) > 0 ? root.parent.width : 1920
    readonly property real screenHeight: (root.parent?.height ?? 0) > 0 ? root.parent.height : 1080
    readonly property real minimumSpawnY: Math.max(
        (GlobalStates.barTopClearanceByScreen[screenName] ?? 0)
            + Appearance.sizes.hyprlandGapsOut
            + 12,
        72
    )

    // Resizing
    function getXResizeDirection(x) {
        return (x < root.resizeMargin) ? -1 : (x > root.width - root.resizeMargin) ? 1 : 0
    }
    function getYResizeDirection(y) {
        return (y < root.resizeMargin) ? -1 : (y > root.height - root.resizeMargin) ? 1 : 0
    }
    hoverEnabled: true
    property bool resizable: true
    property bool resizing: false
    property int resizeXDirection: 0
    property int resizeYDirection: 0
    property real resizeStartMouseX: 0
    property real resizeStartMouseY: 0
    property real resizeStartX: 0
    property real resizeStartY: 0
    property real resizeStartWidth: 0
    property real resizeStartHeight: 0
    property real resizeContentWidth: 0
    property real resizeContentHeight: 0
    preventStealing: resizing
    property bool draggableWhenPinned: persistentStateEntry.draggableWhenPinned ?? false
    readonly property bool bodyDragEnabledWhenPinned: draggableWhenPinned && actuallyPinned && !GlobalStates.overlayOpen
    draggable: GlobalStates.overlayOpen || bodyDragEnabledWhenPinned
    drag.target: undefined
    animateXPos: !(resizing || titleBarDragHandler.active || bodyDragHandler.active)
    animateYPos: !(resizing || titleBarDragHandler.active || bodyDragHandler.active)
    z: (resizing || titleBarDragHandler.active || bodyDragHandler.active) ? 2 : 1
    cursorShape: {
        if (!root.resizable || titleBarDragHandler.active || bodyDragHandler.active)
            return Qt.ArrowCursor;
        const horizontal = root.resizing ? root.resizeXDirection : getXResizeDirection(mouseX);
        const vertical = root.resizing ? root.resizeYDirection : getYResizeDirection(mouseY);
        if (horizontal === 0 && vertical === 0) return Qt.ArrowCursor;
        if (vertical === 0) return Qt.SizeHorCursor;
        if (horizontal === 0) return Qt.SizeVerCursor;
        return horizontal === vertical ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor;
    }

    // Geometry is stored as fractions of the current screen size so the same
    // widget position scales across monitors of different sizes. Legacy
    // absolute-pixel values written by older code are >= 2 and are used as-is
    // until savePosition rewrites them as fractions.
    function resolveMetric(stored, screenDim) {
        return stored >= 2 ? stored : stored * screenDim
    }

    function storedMetric(field) {
        return persistentStateEntry[field];
    }

    function resolveStoredMetric(field, screenDim) {
        return resolveMetric(storedMetric(field), screenDim);
    }

    function resolvedY() {
        const restoredY = Math.round(resolveStoredMetric("y", root.screenHeight) - root.effectiveTitleBarHeight);
        if (storedMetric("y") > 0)
            return restoredY;
        return Math.max(restoredY, root.minimumSpawnY);
    }

    // Positioning & sizing
    x: Math.round(resolveStoredMetric("x", root.screenWidth))
    y: root.resolvedY()
    pinned: persistentStateEntry.pinned
    clickthrough: persistentStateEntry.clickthrough
    drag {
        minimumX: 0
        minimumY: -root.effectiveTitleBarHeight
        maximumX: root.parent?.width - root.width
        maximumY: root.parent?.height - root.height
    }
    opacity: (GlobalStates.overlayOpen || !clickthrough) ? 1.0 : Config.options.overlay.clickthroughOpacity

    // Guarded states & registration funcs
    readonly property bool isWidgetOpen: (Persistent.states.overlay.open ?? []).includes(identifier)
    property bool actuallyPinned: pinned && isWidgetOpen
    property bool actuallyClickable: actuallyPinned && (!clickthrough || bodyDragEnabledWhenPinned)
    property bool actuallyDragHandleClickable: false
    onActuallyPinnedChanged: reportPinnedState();
    onActuallyClickableChanged: reportClickableState();
    onActuallyDragHandleClickableChanged: reportClickableState();
    function reportPinnedState() {
        if (identifier.length > 0)
            OverlayContext.pin(identifier, actuallyPinned);
    }
    function reportClickableState() {
        if (contentItem)
            OverlayContext.registerClickableWidget(contentItem, actuallyClickable);
        if (titleBar)
            OverlayContext.registerClickableWidget(titleBar, actuallyDragHandleClickable);
    }

    // Self-registeration with OverlayContext
    Component.onCompleted: {
        reportPinnedState();
        reportClickableState();
        if (root.actuallyPinned)
            Qt.callLater(() => GlobalStates.rememberOverlayScreen(root.screenName));
    }
    Component.onDestruction: {
        if (contentItem)
            OverlayContext.registerClickableWidget(contentItem, false);
        if (titleBar)
            OverlayContext.registerClickableWidget(titleBar, false);
        if (identifier.length > 0)
            OverlayContext.pin(identifier, false);
    }

    // Hooks
    onPressed: (event) => {
        // We're only interested in handling resize here
        // Early returns
        if (!root.resizable) {
            event.accepted = false;
            return;
        }
        if (root.resizeMargin < event.x && event.x < root.width - root.resizeMargin &&
            root.resizeMargin < event.y && event.y < root.height - root.resizeMargin) {
            event.accepted = false;
            return;
        }
        // Snapshot the displayed geometry: stored y includes title-bar space,
        // and layout constraints can make the actual content larger than saved.
        const pointer = root.mapToItem(root.parent, event.x, event.y);
        root.resizeStartMouseX = pointer.x;
        root.resizeStartMouseY = pointer.y;
        root.resizeStartX = root.x;
        root.resizeStartY = root.y;
        root.resizeStartWidth = contentContainer.width;
        root.resizeStartHeight = contentContainer.height;
        root.resizeContentWidth = root.resizeStartWidth;
        root.resizeContentHeight = root.resizeStartHeight;
        root.resizeXDirection = getXResizeDirection(event.x);
        root.resizeYDirection = getYResizeDirection(event.y);
        root.resizing = true;
    }
    onPositionChanged: (event) => {
        if (!resizing) return;
        const pointer = root.mapToItem(root.parent, event.x, event.y);
        const dx = pointer.x - root.resizeStartMouseX;
        const dy = pointer.y - root.resizeStartMouseY;
        root.resizeContentWidth = Math.max(root.minimumWidth,
            root.resizeStartWidth + dx * root.resizeXDirection);
        root.resizeContentHeight = Math.max(root.minimumHeight,
            root.resizeStartHeight + dy * root.resizeYDirection);
        root.x = root.resizeStartX + (root.resizeXDirection === -1
            ? root.resizeStartWidth - root.resizeContentWidth : 0);
        root.y = root.resizeStartY + (root.resizeYDirection === -1
            ? root.resizeStartHeight - root.resizeContentHeight : 0);
    }
    onReleased: root.finishResize()
    onCanceled: root.finishResize()

    function finishResize() {
        if (!root.resizing) return;
        root.savePosition(root.x, root.y, root.resizeContentWidth, root.resizeContentHeight);
        root.resizing = false;
    }

    function close() {
        Persistent.states.overlay.open = (Persistent.states.overlay.open ?? []).filter(type => type !== root.identifier);
    }

    function togglePinned() {
        const nextPinned = !persistentStateEntry.pinned;
        persistentStateEntry.pinned = nextPinned;
        if (nextPinned)
            GlobalStates.rememberOverlayScreen(root.screenName);
    }

    function toggleClickthrough() {
        persistentStateEntry.clickthrough = !persistentStateEntry.clickthrough;
    }

    function toggleDraggableWhenPinned() {
        persistentStateEntry.draggableWhenPinned = !persistentStateEntry.draggableWhenPinned;
    }

    function savePosition(xPos = root.x, yPos = root.y, width = contentContainer.width, height = contentContainer.height) {
        const sw = root.screenWidth
        const sh = root.screenHeight
        persistentStateEntry.x = xPos / sw
        persistentStateEntry.y = (yPos + root.effectiveTitleBarHeight) / sh
        persistentStateEntry.width = width / sw
        persistentStateEntry.height = height / sh
        // Drag handlers and resizing assign x/y directly. Restore the bindings
        // so monitor size changes and title-bar visibility still reposition us.
        root.x = Qt.binding(() => Math.round(root.resolveStoredMetric("x", root.screenWidth)))
        root.y = Qt.binding(() => root.resolvedY())
    }

    function center() {
        const targetX = (root.parent.width - contentColumn.width) / 2 - root.resizeMargin
        const targetY = (root.parent.height - contentContainer.height) / 2 + border.border.width - root.resizeMargin - root.effectiveTitleBarHeight
        root.x = targetX
        root.y = targetY
        root.savePosition(targetX, targetY)
    }

    visible: GlobalStates.overlayOpen || actuallyPinned
    implicitWidth: contentColumn.implicitWidth + resizeMargin * 2
    implicitHeight: contentColumn.implicitHeight + resizeMargin * 2

    QtObject {
        id: fallbackPersistentStateEntry
        property bool pinned: false
        property bool clickthrough: false
        property bool draggableWhenPinned: false
        property real x: 0
        property real y: 0
        property real width: 0
        property real height: 0
    }

    Rectangle {
        id: border
        anchors {
            fill: parent
            margins: root.resizeMargin
        }
        color: ColorUtils.transparentize(Appearance.colors.colLayer1Base, (root.fancyBorders && GlobalStates.overlayOpen) ? 0 : 1)
        radius: root.radius
        border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, GlobalStates.overlayOpen ? 0 : 1)
        border.width: 1

        layer.enabled: GlobalStates.overlayOpen && root.useOpacityMaskLayer
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: border.width
                height: border.height
                radius: root.radius
            }
        }

        ColumnLayout {
            id: contentColumn
            z: root.fancyBorders ? 0 : -1
            anchors.fill: parent
            spacing: 0

            // Title bar
            Rectangle {
                id: titleBar
                visible: root.showTitleBar
                opacity: root.showTitleBar ? 1 : 0
                Layout.fillWidth: true
                implicitWidth: titleBarRow.implicitWidth + root.padding * 2
                implicitHeight: root.showTitleBar ? titleBarRow.implicitHeight + root.padding * 2 : 0
                color: root.fancyBorders ? "transparent" : Appearance.colors.colLayer1Base
                // border.color: Appearance.colors.colOutlineVariant
                // border.width: 1
                
                DragHandler {
                    id: titleBarDragHandler
                    property bool activated: false
                    acceptedButtons: Qt.LeftButton
                    target: (root.draggable && !root.resizing) ? root : null
                    xAxis.minimum: 0
                    xAxis.maximum: root.parent?.width - root.width
                    yAxis.minimum: -root.effectiveTitleBarHeight
                    yAxis.maximum: root.parent?.height - root.height
                    onActiveChanged: {
                        if (active) {
                            activated = true
                            return
                        }
                        if (!activated)
                            return
                        activated = false
                        root.savePosition()
                    }
                }

                RowLayout {
                    id: titleBarRow
                    anchors {
                        fill: parent
                        margins: root.padding
                    }
                    spacing: 2

                    MaterialSymbol {
                        text: root.materialSymbol
                        Layout.leftMargin: 6
                        iconSize: 20
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: 4
                    }
                    
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        // Give the title remaining space without making its
                        // natural text width a minimum for the entire panel.
                        Layout.preferredWidth: 0
                        text: root.title
                        elide: Text.ElideRight
                    }

                    TitlebarButton {
                        visible: root.showCenterButton
                        materialSymbol: "recenter"
                        onClicked: root.center()
                        StyledToolTip {
                            text: "Center"
                        }
                    }

                    TitlebarButton {
                        visible: root.pinned
                        materialSymbol: "drag_pan"
                        toggled: root.draggableWhenPinned
                        onClicked: root.toggleDraggableWhenPinned()
                        StyledToolTip {
                            text: "Draggable when pinned"
                        }
                    }

                    TitlebarButton {
                        visible: (root.pinned && root.showClickabilityButton)
                        materialSymbol: "mouse"
                        toggled: !root.clickthrough
                        onClicked: root.toggleClickthrough()
                        StyledToolTip {
                            text: "Clickable when pinned"
                        }
                    }

                    TitlebarButton {
                        materialSymbol: "keep"
                        toggled: root.pinned
                        onClicked: root.togglePinned()
                        StyledToolTip {
                            text: "Pin"
                        }
                    }

                    TitlebarButton {
                        materialSymbol: "close"
                        onClicked: root.close()
                        StyledToolTip {
                            text: "Close"
                        }
                    }
                }
            }

            // Content
            Item {
                id: contentContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: root.fancyBorders ? root.padding : 0
                Layout.topMargin: -border.border.width // Border of a rectangle is drawn inside its bounds, so we do this to make the gap not too big
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                implicitWidth: Math.max(root.resizing ? root.resizeContentWidth
                    : root.resolveStoredMetric("width", root.screenWidth), root.minimumWidth)
                implicitHeight: Math.max(root.resizing ? root.resizeContentHeight
                    : root.resolveStoredMetric("height", root.screenHeight), root.minimumHeight)
                children: [root.contentItem]

                DragHandler {
                    id: bodyDragHandler
                    property bool activated: false
                    acceptedButtons: Qt.LeftButton
                    target: (root.bodyDragEnabledWhenPinned && !root.resizing) ? root : null
                    xAxis.minimum: 0
                    xAxis.maximum: root.parent?.width - root.width
                    yAxis.minimum: 0
                    yAxis.maximum: root.parent?.height - root.height
                    onActiveChanged: {
                        if (active) {
                            activated = true
                            return
                        }
                        if (!activated)
                            return
                        activated = false
                        root.savePosition()
                    }
                }
            }
        }
    }


    component TitlebarButton: RippleButton {
        id: titlebarButton
        required property string materialSymbol
        buttonRadius: height / 2
        implicitHeight: contentItem.implicitHeight
        implicitWidth: implicitHeight
        padding: 0

        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive

        contentItem: Item {
            anchors.centerIn: parent
            implicitWidth: 30
            implicitHeight: 30

            MaterialSymbol {
                id: iconWidget
                anchors.centerIn: parent
                iconSize: 20
                text: titlebarButton.materialSymbol
                fill: titlebarButton.toggled
                color: titlebarButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
            }
        }
    }
}
