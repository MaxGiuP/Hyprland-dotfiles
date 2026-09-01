import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property real maxWindowPreviewHeight: 200
    property real maxWindowPreviewWidth: 300
    property real windowControlsHeight: 30
    property real buttonPadding: 5

    property Item previewTargetButton
    property Item previewAnchorButton
    property Item contextMenuButton
    property bool dockDragging: false
    property string draggedPinnedAppId: ""
    property string dropTargetPinnedAppId: ""
    property bool launchStripeShown: false
    property bool launchCompleting: false
    property real launchProgress: 0
    property int launchCompletionDuration: 420
    property string launchingAppId: ""
    property int launchingInitialWindowCount: 0
    property bool requestDockShow: previewPopup.show || dockDragging || contextMenuButton !== null || launchStripeShown

    function beginAppLaunch(appId, initialWindowCount) {
        launchAdvanceAnimation.stop()
        launchCompleteAnimation.stop()
        launchHideTimer.stop()
        launchResetTimer.stop()
        launchTimeoutTimer.stop()

        root.launchingAppId = TaskbarApps.canonicalAppId(appId)
        root.launchingInitialWindowCount = Math.max(0, Number(initialWindowCount) || 0)
        root.launchCompleting = false
        root.launchProgress = 0.04
        root.launchStripeShown = true
        launchAdvanceAnimation.restart()
        launchTimeoutTimer.restart()
    }

    function observeAppWindows(appId, windowCount) {
        if (!root.launchStripeShown || root.launchCompleting)
            return
        if (TaskbarApps.canonicalAppId(appId) !== root.launchingAppId)
            return
        if (Number(windowCount) > root.launchingInitialWindowCount)
            root.completeAppLaunch()
    }

    function completeAppLaunch() {
        if (!root.launchStripeShown || root.launchCompleting)
            return

        root.launchCompleting = true
        launchAdvanceAnimation.stop()
        launchTimeoutTimer.stop()
        root.launchCompletionDuration = Math.round(220 + 560 * (1 - root.launchProgress))
        launchCompleteAnimation.restart()
    }

    NumberAnimation {
        id: launchAdvanceAnimation
        target: root
        property: "launchProgress"
        to: 0.96
        duration: launchTimeoutTimer.interval
        easing.type: Easing.Linear
    }

    NumberAnimation {
        id: launchCompleteAnimation
        target: root
        property: "launchProgress"
        to: 1
        duration: root.launchCompletionDuration
        easing.type: Easing.InOutCubic
        onFinished: launchHideTimer.restart()
    }

    Timer {
        id: launchTimeoutTimer
        interval: 12000
        repeat: false
        onTriggered: root.completeAppLaunch()
    }

    Timer {
        id: launchHideTimer
        interval: 220
        repeat: false
        onTriggered: {
            root.launchStripeShown = false
            launchResetTimer.restart()
        }
    }

    Timer {
        id: launchResetTimer
        interval: 260
        repeat: false
        onTriggered: {
            root.launchProgress = 0
            root.launchCompleting = false
            root.launchingAppId = ""
            root.launchingInitialWindowCount = 0
        }
    }

    function cancelPreviewImmediately() {
        root.previewTargetButton = null
        root.previewAnchorButton = null
        updateTimer.stop()
        previewPopup.show = false
    }

    function clearPreviewState() {
        root.previewTargetButton = null
    }

    function showPreviewForButton(button) {
        if (!button || dockDragging || button.toplevels.length === 0) {
            clearPreviewState()
            return
        }

        root.previewTargetButton = button
        root.previewAnchorButton = button
    }

    function hidePreviewForButton(button) {
        if (root.previewTargetButton === button) {
            root.previewTargetButton = null
        }
    }

    function clearDragState() {
        root.dockDragging = false
        root.draggedPinnedAppId = ""
        root.dropTargetPinnedAppId = ""
    }

    Layout.fillHeight: true
    Layout.topMargin: Appearance.sizes.hyprlandGapsOut // why does this work
    implicitWidth: listView.implicitWidth
    
    StyledListView {
        id: listView
        spacing: 2
        orientation: ListView.Horizontal
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        implicitWidth: contentWidth

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        model: ScriptModel {
            objectProp: "appId"
            values: TaskbarApps.apps
        }
        delegate: DockAppButton {
            required property var modelData
            appToplevel: modelData
            appListRoot: root

            topInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
            bottomInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
        }
    }

    PopupWindow {
        id: previewPopup
        property var appTopLevel: root.previewAnchorButton?.appToplevel
        property bool shouldShow: {
            if (root.dockDragging) return false;
            if (root.previewTargetButton !== null) return true;
            return popupMouseArea.containsMouse && previewPopup.show;
        }
        property bool show: false

        onShouldShowChanged: {
            if (shouldShow) {
                // show = true;
                updateTimer.restart();
            } else {
                updateTimer.restart();
            }
        }
        Timer {
            id: updateTimer
            interval: 100
            onTriggered: {
                previewPopup.show = previewPopup.shouldShow
                if (!previewPopup.show && !popupMouseArea.containsMouse && root.previewTargetButton === null) {
                    root.previewAnchorButton = null
                }
            }
        }
        anchor {
            window: root.QsWindow.window
            adjustment: PopupAdjustment.None
            gravity: Edges.Top | Edges.Right
            edges: Edges.Top | Edges.Left
        }
        // Keep surface alive after first show to prevent Wayland input routing corruption
        property bool initialized: false
        onShowChanged: if (show && !initialized) initialized = true

        mask: Region {
            item: previewPopup.show ? popupBackground : emptyMaskRegion
        }
        visible: initialized || popupBackground.visible
        color: "transparent"
        implicitWidth: root.QsWindow.window?.width ?? 1

        Item { id: emptyMaskRegion; width: 0; height: 0 }
        implicitHeight: popupMouseArea.implicitHeight + root.windowControlsHeight + Appearance.sizes.elevationMargin * 2

        MouseArea {
            id: popupMouseArea
            anchors.bottom: parent.bottom
            implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: root.maxWindowPreviewHeight + root.windowControlsHeight + Appearance.sizes.elevationMargin * 2
            hoverEnabled: true
            x: {
                if (!root.previewAnchorButton) return x
                const itemCenter = root.QsWindow?.mapFromItem(root.previewAnchorButton, root.previewAnchorButton.width / 2, 0);
                if (!itemCenter) return x
                return itemCenter.x - width / 2
            }
            StyledRectangularShadow {
                target: popupBackground
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
            Rectangle {
                id: popupBackground
                property real padding: 5
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                clip: true
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Appearance.sizes.elevationMargin
                anchors.horizontalCenter: parent.horizontalCenter
                implicitHeight: previewRowLayout.implicitHeight + padding * 2
                implicitWidth: previewRowLayout.implicitWidth + padding * 2
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: previewRowLayout
                    anchors.centerIn: parent
                    Repeater {
                        model: ScriptModel {
                            values: Array.from(previewPopup.appTopLevel?.toplevels ?? []).filter(toplevel => toplevel !== null && toplevel !== undefined)
                        }
                        RippleButton {
                            id: windowButton
                            required property var modelData
                            padding: 0
                            middleClickAction: () => {
                                windowButton.modelData?.close();
                            }
                            onClicked: {
                                windowButton.modelData?.activate();
                            }
                            contentItem: ColumnLayout {
                                implicitWidth: screencopyView.implicitWidth
                                implicitHeight: screencopyView.implicitHeight

                                ButtonGroup {
                                    contentWidth: parent.width - anchors.margins * 2
                                    Rectangle {
                                        id: previewTitleBackground
                                        Layout.fillWidth: true
                                        implicitWidth: previewTitle.implicitWidth + 10
                                        implicitHeight: previewTitle.implicitHeight + 10
                                        color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                        radius: Appearance.rounding.small
                                        StyledText {
                                            id: previewTitle
                                            anchors.fill: parent
                                            anchors.margins: 5
                                            Layout.fillWidth: true
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            text: windowButton.modelData?.title
                                            elide: Text.ElideRight
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                    }
                                    GroupButton {
                                        id: closeButton
                                        colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                        baseWidth: windowControlsHeight
                                        baseHeight: windowControlsHeight
                                        buttonRadius: Appearance.rounding.full
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "close"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        onClicked: {
                                            windowButton.modelData?.close();
                                        }
                                    }
                                }
                                ScreencopyView {
                                    id: screencopyView
                                    readonly property var previewSource: previewPopup.show
                                        ? HyprlandData.captureSourceForToplevel(windowButton.modelData, false)
                                        : null
                                    captureSource: previewSource
                                    live: previewSource !== null
                                    paintCursor: true
                                    constraintSize: Qt.size(root.maxWindowPreviewWidth, root.maxWindowPreviewHeight)
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: screencopyView.width
                                            height: screencopyView.height
                                            radius: Appearance.rounding.small
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
