pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Item {
    id: root

    signal appLaunched()
    property var returnToSearchAction: null

    readonly property int columns: 8
    readonly property int cellHeight: 108
    readonly property int iconSize: 52
    property int selectedAppIndex: 0
    readonly property var navigationApps: root.recentApps.concat(root.sortedApps)

    function activateFirstApp() {
        if (root.navigationApps.length === 0)
            return
        root.selectedAppIndex = 0
        root.forceActiveFocus()
    }

    function moveSelection(delta) {
        const count = root.navigationApps.length
        if (count === 0)
            return
        root.selectedAppIndex = Math.max(0, Math.min(count - 1, root.selectedAppIndex + delta))
    }

    function launchSelectedApp() {
        const app = root.navigationApps[root.selectedAppIndex]
        if (!app)
            return
        AppLaunch.launchDesktopEntry(app)
        root.appLaunched()
    }

    function handleKey(key) {
        if (key === Qt.Key_Right) {
            root.moveSelection(1)
        } else if (key === Qt.Key_Left) {
            root.moveSelection(-1)
        } else if (key === Qt.Key_Down) {
            root.moveSelection(root.columns)
        } else if (key === Qt.Key_Up) {
            if (root.selectedAppIndex < root.columns)
                root.returnToSearchAction?.()
            else
                root.moveSelection(-root.columns)
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            root.launchSelectedApp()
        } else if (key === Qt.Key_Escape) {
            root.returnToSearchAction?.()
        } else {
            return false
        }
        return true
    }

    focus: GlobalStates.overviewOpen && GlobalStates.overviewDrawerMode
    Keys.onPressed: event => {
        if (!root.handleKey(event.key))
            return
        event.accepted = true
    }

    // All apps sorted A-Z
    readonly property var sortedApps: {
        return AppSearch.list.slice().sort((a, b) => {
            const aName = (a?.name ?? "").toLowerCase()
            const bName = (b?.name ?? "").toLowerCase()
            return aName.localeCompare(bName)
        })
    }

    readonly property var recentApps: {
        const appsById = new Map(AppSearch.list.map(app => [String(app?.id ?? ""), app]))
        return Array.from(Persistent.states.drawer.recentAppIds ?? [])
            .map(id => appsById.get(id))
            .filter(app => app !== undefined)
            .slice(0, root.columns)
    }

    // Build recent apps first, followed by the complete A-Z application list.
    function buildRowModel(apps, recentApps) {
        const COLS = root.columns
        const rows = [
            { type: "section", label: Translation.tr("Recently used") },
            recentApps.length > 0
                ? { type: "apps", apps: recentApps.slice(0, COLS), navigationOffset: 0 }
                : { type: "emptyRecent" },
            { type: "section", label: Translation.tr("All applications") }
        ]
        let currentLetter = null
        let currentRow = []
        let currentRowOffset = recentApps.length
        let navigationIndex = recentApps.length

        for (const app of apps) {
            const firstChar = (app?.name ?? "").charAt(0).toUpperCase()
            const letter = /[A-Z]/.test(firstChar) ? firstChar : "#"

            if (letter !== currentLetter) {
                if (currentRow.length > 0) {
                    rows.push({ type: "apps", apps: currentRow.slice(), navigationOffset: currentRowOffset })
                    currentRow = []
                }
                rows.push({ type: "header", letter: letter })
                currentLetter = letter
            }

            if (currentRow.length === 0)
                currentRowOffset = navigationIndex
            currentRow.push(app)
            navigationIndex += 1
            if (currentRow.length >= COLS) {
                rows.push({ type: "apps", apps: currentRow.slice(), navigationOffset: currentRowOffset })
                currentRow = []
            }
        }
        if (currentRow.length > 0)
            rows.push({ type: "apps", apps: currentRow.slice(), navigationOffset: currentRowOffset })

        return rows
    }

    // Click-outside dismiss overlay — sits above the app grid but below the menu
    MouseArea {
        anchors.fill: parent
        visible: contextMenu.visible
        z: 99
        acceptedButtons: Qt.AllButtons
        onClicked: contextMenu.visible = false
    }

    // Context menu — content lives inside the background Rectangle so the
    // rounded corners correctly contain everything (DesktopContextMenu pattern)
    Item {
        id: contextMenu
        visible: false
        z: 100
        property var targetApp: null

        width: menuBackground.width
        height: menuBackground.height

        Rectangle {
            id: menuBackground
            width: 180
            height: menuItems.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Qt.rgba(Appearance.colors.colLayer1.r,
                           Appearance.colors.colLayer1.g,
                           Appearance.colors.colLayer1.b, 1.0)
            border.color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.45)
                shadowBlur: 0.25
                shadowVerticalOffset: 8
            }

            ColumnLayout {
                id: menuItems
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 8
                    leftMargin: 8
                    rightMargin: 8
                }
                spacing: 2

                // Open
                Item {
                    implicitHeight: 34
                    Layout.fillWidth: true
                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: openHover.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                        Behavior on color { ColorAnimation { duration: 80 } }
                    }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 8
                        IconImage {
                            source: Quickshell.iconPath("document-open")
                            implicitSize: 16
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: "Open"
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: 13
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                    MouseArea {
                        id: openHover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            contextMenu.visible = false
                            AppLaunch.launchDesktopEntry(contextMenu.targetApp)
                            root.appLaunched()
                        }
                    }
                }

                // Separator
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.1)
                }

                // Delete
                Item {
                    implicitHeight: 34
                    Layout.fillWidth: true
                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: deleteHover.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                        Behavior on color { ColorAnimation { duration: 80 } }
                    }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 8
                        IconImage {
                            source: Quickshell.iconPath("user-trash")
                            implicitSize: 16
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: "Delete"
                            color: Appearance.m3colors.m3error
                            font.pixelSize: 13
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                    MouseArea {
                        id: deleteHover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            contextMenu.visible = false
                            const app = contextMenu.targetApp
                            if (!app) return
                            const exec = (app.command ?? [])[0] ?? ""
                            const innerCmd = `pkg=$(pacman -Qoq "$(which '${StringUtils.shellSingleQuoteEscape(exec)}')\" 2>/dev/null); sudo pacman -Rns \"$pkg\"; echo; read -p 'Done. Press Enter.'`
                            Quickshell.execDetached(["bash", "-c", `${Config.options.apps.terminal} -e bash -c '${StringUtils.shellSingleQuoteEscape(innerCmd)}'`])
                            root.appLaunched()
                        }
                    }
                }
            }
        }
    }

    // Frosted glass panel — rounded top corners, squared-off at screen bottom, gaps on sides.
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 160
        anchors.rightMargin: 160
        topLeftRadius: Appearance.rounding.large
        topRightRadius: Appearance.rounding.large
        color: {
            const c = Appearance.m3colors.m3surfaceContainer
            const factor = Appearance.m3colors.darkmode ? 1.0 : 0.6
            return Qt.rgba(c.r * factor, c.g * factor, c.b * factor, 0.88)
        }
        border.width: 8
        border.color: Appearance.m3colors.m3outlineVariant
        // Negative bottom margin pushes the rectangle's bottom edge beyond the screen,
        // so the compositor clips off the bottom border entirely — clean borderless bottom.
        anchors.bottomMargin: -8
    }

    ListView {
        id: appList
        anchors {
            fill: parent
            leftMargin: 168
            rightMargin: 168
            topMargin: 12
            bottomMargin: 12
        }
        clip: true
        // Reusing delegates backed by this JavaScript row model can crash Qt's
        // QML model bridge when the drawer is exposed. Keep delegates stable.
        reuseItems: false
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        model: root.buildRowModel(root.sortedApps, root.recentApps)

        delegate: Item {
            id: rowItem
            required property var modelData
            required property int index
            width: appList.width
            height: rowItem.modelData.type === "header" || rowItem.modelData.type === "section"
                ? 48
                : rowItem.modelData.type === "emptyRecent" ? 56 : root.cellHeight

            // Section header — pill badge + horizontal rule
            RowLayout {
                visible: rowItem.modelData.type === "header" || rowItem.modelData.type === "section"
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 4
                    rightMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                spacing: 10

                Rectangle {
                    implicitWidth: headerLabel.implicitWidth + 20
                    implicitHeight: headerLabel.implicitHeight + 12
                    radius: height / 2
                    color: Appearance.colors.colPrimaryContainer

                    Text {
                        id: headerLabel
                        anchors.centerIn: parent
                        text: rowItem.modelData.type === "header"
                            ? (rowItem.modelData.letter ?? "")
                            : (rowItem.modelData.label ?? "")
                        color: Appearance.colors.colOnPrimaryContainer
                        font.pixelSize: Appearance.font.pixelSize.small + 2
                        font.weight: Font.Bold
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.2
                }
            }

            Text {
                visible: rowItem.modelData.type === "emptyRecent"
                anchors.centerIn: parent
                text: Translation.tr("Applications you launch will appear here")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                opacity: 0.75
            }

            // Apps row
            Row {
                visible: rowItem.modelData.type === "apps"
                anchors.fill: parent
                spacing: 0

                Repeater {
                    model: rowItem.modelData.type === "apps" ? (rowItem.modelData.apps ?? []) : []
                    delegate: Item {
                        id: appCell
                        required property var modelData
                        required property int index
                        property var app: appCell.modelData
                        readonly property int navigationIndex: (rowItem.modelData.navigationOffset ?? 0) + appCell.index
                        width: appList.width / root.columns
                        height: root.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 6
                            radius: Appearance.rounding.normal
                            color: appCell.navigationIndex === root.selectedAppIndex
                                ? Qt.rgba(
                                    Appearance.colors.colPrimary.r,
                                    Appearance.colors.colPrimary.g,
                                    Appearance.colors.colPrimary.b,
                                    0.24
                                  )
                                : appArea.containsMouse
                                ? Qt.rgba(
                                    Appearance.colors.colPrimary.r,
                                    Appearance.colors.colPrimary.g,
                                    Appearance.colors.colPrimary.b,
                                    0.12
                                  )
                                : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            IconImage {
                                Layout.alignment: Qt.AlignHCenter
                                source: AppSearch.resolvedIconPath(appCell.app?.icon ?? "")
                                implicitSize: root.iconSize
                                scale: appArea.containsMouse ? 1.08 : 1.0
                                Behavior on scale {
                                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: (appList.width / root.columns) - 16
                                text: appCell.app?.name ?? ""
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.small - 1
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                            }
                        }

                        MouseArea {
                            id: appArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selectedAppIndex = appCell.navigationIndex
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    contextMenu.targetApp = appCell.app
                                    const pos = appCell.mapToItem(root, mouse.x, mouse.y)
                                    contextMenu.x = Math.min(pos.x, root.width - contextMenu.width - 4)
                                    contextMenu.y = Math.min(pos.y, root.height - contextMenu.height - 4)
                                    contextMenu.visible = true
                                } else {
                                    AppLaunch.launchDesktopEntry(appCell.app)
                                    root.appLaunched()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
