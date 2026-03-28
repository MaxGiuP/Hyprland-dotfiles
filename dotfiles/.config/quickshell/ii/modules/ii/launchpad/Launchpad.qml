pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: drawerScope

    readonly property var drawerScreenObject: Quickshell.screens.find(s => s.name === GlobalStates.drawerScreen)
                                               ?? Quickshell.screens[0]
                                               ?? null

    readonly property int columns: 5
    readonly property int cellHeight: 148
    readonly property int iconSize: 76
    readonly property int maxContentWidth: 1280

    // All apps sorted A-Z
    readonly property var sortedApps: {
        const apps = AppSearch.list.slice()
        apps.sort((a, b) => {
            const aName = (a?.name ?? "").toLowerCase()
            const bName = (b?.name ?? "").toLowerCase()
            return aName.localeCompare(bName)
        })
        return apps
    }

    // Build a flat row model: [{type:"header", letter:"A"}, {type:"apps", apps:[...]}, ...]
    function buildRowModel(apps, showSections) {
        const COLS = drawerScope.columns
        const rows = []
        let currentLetter = null
        let currentRow = []

        for (const app of apps) {
            const firstChar = (app?.name ?? "").charAt(0).toUpperCase()
            const letter = /[A-Z]/.test(firstChar) ? firstChar : "#"

            if (showSections && letter !== currentLetter) {
                if (currentRow.length > 0) {
                    rows.push({ type: "apps", apps: currentRow.slice() })
                    currentRow = []
                }
                rows.push({ type: "header", letter: letter })
                currentLetter = letter
            }

            currentRow.push(app)
            if (currentRow.length >= COLS) {
                rows.push({ type: "apps", apps: currentRow.slice() })
                currentRow = []
            }
        }
        if (currentRow.length > 0)
            rows.push({ type: "apps", apps: currentRow.slice() })

        return rows
    }

    // ── Panel window ──────────────────────────────────────────────────────
    PanelWindow {
        id: panelWindow
        screen: drawerScope.drawerScreenObject
        // Keep surface alive to prevent Quickshell input routing issues on destroy/recreate
        visible: true

        WlrLayershell.namespace: "quickshell:drawer"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }

        // Input mask: covers full screen when open, tiny invisible area otherwise
        mask: Region { item: drawerMaskItem }
        Item {
            id: drawerMaskItem
            x: GlobalStates.drawerOpen ? 0 : -2
            y: GlobalStates.drawerOpen ? 0 : -2
            width:  GlobalStates.drawerOpen ? parent.width  : 1
            height: GlobalStates.drawerOpen ? parent.height : 1
        }

        Timer {
            id: focusGrabDelay
            interval: 1; repeat: false
            onTriggered: {
                if (!GlobalStates.drawerOpen) return
                searchField.forceActiveFocus()
                GlobalFocusGrab.addDismissable(panelWindow)
            }
        }

        Timer {
            id: closeDrawerTimer
            interval: 1; repeat: false
            onTriggered: GlobalStates.closeDrawer()
        }

        Shortcut {
            sequence: "Escape"
            enabled: GlobalStates.drawerOpen
            onActivated: {
                if (searchField.text.length > 0)
                    searchField.text = ""
                else
                    GlobalStates.closeDrawer()
            }
        }

        Connections {
            target: GlobalStates
            function onDrawerOpenChanged() {
                if (!GlobalStates.drawerOpen) {
                    focusGrabDelay.stop()
                    closeDrawerTimer.stop()
                    GlobalFocusGrab.removeDismissable(panelWindow)
                    if (searchField.activeFocus)
                        contentRoot.forceActiveFocus()
                    searchField.text = ""
                } else {
                    GlobalStates.drawerScreen = GlobalStates.resolvedDrawerScreen()
                    focusGrabDelay.restart()
                }
            }
        }

        Connections {
            target: HyprlandData
            function onMonitorsChanged() {
                if (!GlobalStates.drawerOpen) return
                const focused = HyprlandData.monitors.find(m => m.focused)?.name
                            ?? Hyprland.focusedMonitor?.name ?? ""
                if (focused.length > 0 && focused !== GlobalStates.drawerScreen)
                    GlobalStates.closeDrawer()
            }
        }

        Component.onDestruction: {
            focusGrabDelay.stop()
            closeDrawerTimer.stop()
            GlobalFocusGrab.removeDismissable(panelWindow)
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() { GlobalStates.closeDrawer() }
        }

        // ── Full-screen content ────────────────────────────────────────────
        Item {
            id: contentRoot
            anchors.fill: parent

            // Upward slide + fade-in animation (Android drawer style)
            opacity: GlobalStates.drawerOpen ? 1.0 : 0.0
            property real slideY: GlobalStates.drawerOpen ? 0 : height * 0.22
            transform: Translate { y: contentRoot.slideY }

            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            Behavior on slideY  { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }

            // Dark tinted background
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0.02, 0.01, 0.05, 0.86)
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: GlobalStates.closeDrawer()
                }
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(
                    Appearance.colors.colPrimary.r,
                    Appearance.colors.colPrimary.g,
                    Appearance.colors.colPrimary.b,
                    0.09
                )
            }

            // ── Content column ─────────────────────────────────────────
            ColumnLayout {
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                }
                width: Math.min(parent.width - 40, drawerScope.maxContentWidth)
                spacing: 10

                // ── Search bar ────────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.topMargin: 36
                    Layout.preferredHeight: 54

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, 520)
                        height: 54
                        radius: 27
                        color: Qt.rgba(1, 1, 1, 0.13)
                        border.color: Qt.rgba(1, 1, 1, 0.22)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 16
                            spacing: 12

                            MaterialSymbol {
                                text: "search"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Qt.rgba(1, 1, 1, 0.75)
                            }

                            TextField {
                                id: searchField
                                Layout.fillWidth: true
                                background: Item {}
                                color: "white"
                                placeholderText: Translation.tr("Search apps\u2026")
                                placeholderTextColor: Qt.rgba(1, 1, 1, 0.45)
                                font.pixelSize: Appearance.font.pixelSize.small
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape) {
                                        if (searchField.text.length > 0)
                                            searchField.text = ""
                                        else
                                            GlobalStates.closeDrawer()
                                        event.accepted = true
                                    }
                                }
                            }

                            MaterialSymbol {
                                visible: searchField.text.length > 0
                                text: "close"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Qt.rgba(1, 1, 1, 0.6)
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: searchField.text = ""
                                }
                            }
                        }
                    }
                }

                // ── App list ──────────────────────────────────────────
                ListView {
                    id: appListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.bottomMargin: 24
                    clip: true
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    readonly property bool isSearching: searchField.text.length > 0
                    readonly property var displayApps: isSearching
                        ? AppSearch.fuzzyQuery(searchField.text)
                        : drawerScope.sortedApps

                    model: drawerScope.buildRowModel(appListView.displayApps, !appListView.isSearching)

                    delegate: Item {
                        id: rowItem
                        required property var modelData
                        required property int index
                        width: appListView.width
                        height: rowItem.modelData.type === "header" ? 38 : drawerScope.cellHeight

                        // Section header
                        Text {
                            visible: rowItem.modelData.type === "header"
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            text: rowItem.modelData.type === "header" ? (rowItem.modelData.letter ?? "") : ""
                            color: Qt.rgba(1, 1, 1, 0.45)
                            font.pixelSize: Appearance.font.pixelSize.small - 1
                            font.weight: Font.Medium
                        }

                        // Apps row
                        Row {
                            visible: rowItem.modelData.type === "apps"
                            anchors.fill: parent

                            Repeater {
                                model: rowItem.modelData.type === "apps" ? (rowItem.modelData.apps ?? []) : []
                                delegate: Item {
                                    id: appCell
                                    required property var modelData
                                    property var app: appCell.modelData
                                    width: appListView.width / drawerScope.columns
                                    height: drawerScope.cellHeight

                                    // Hover background
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        radius: Appearance.rounding.normal
                                        color: appArea.containsMouse
                                            ? Qt.rgba(1, 1, 1, 0.12)
                                            : "transparent"
                                        Behavior on color { ColorAnimation { duration: 110 } }
                                    }

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 10

                                        IconImage {
                                            Layout.alignment: Qt.AlignHCenter
                                            source: Quickshell.iconPath(appCell.app?.icon ?? "", "image-missing")
                                            implicitSize: drawerScope.iconSize
                                            scale: appArea.containsMouse ? 1.08 : 1.0
                                            Behavior on scale {
                                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.preferredWidth: (appListView.width / drawerScope.columns) - 18
                                            text: appCell.app?.name ?? ""
                                            color: "white"
                                            font.pixelSize: Appearance.font.pixelSize.small - 1
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            style: Text.Outline
                                            styleColor: Qt.rgba(0, 0, 0, 0.5)
                                        }
                                    }

                                    MouseArea {
                                        id: appArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            appCell.app?.execute()
                                            GlobalStates.closeDrawer()
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
