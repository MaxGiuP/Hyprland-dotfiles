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

    readonly property int columns: 8
    readonly property int cellHeight: 108
    readonly property int iconSize: 52

    // All apps sorted A-Z
    readonly property var sortedApps: {
        return AppSearch.list.slice().sort((a, b) => {
            const aName = (a?.name ?? "").toLowerCase()
            const bName = (b?.name ?? "").toLowerCase()
            return aName.localeCompare(bName)
        })
    }

    // Build a flat row model: [{type:"header", letter:"A"}, {type:"apps", apps:[...]}, ...]
    function buildRowModel(apps) {
        const COLS = root.columns
        const rows = []
        let currentLetter = null
        let currentRow = []

        for (const app of apps) {
            const firstChar = (app?.name ?? "").charAt(0).toUpperCase()
            const letter = /[A-Z]/.test(firstChar) ? firstChar : "#"

            if (letter !== currentLetter) {
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
                            contextMenu.targetApp?.execute()
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
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        model: root.buildRowModel(root.sortedApps)

        delegate: Item {
            id: rowItem
            required property var modelData
            required property int index
            width: appList.width
            height: rowItem.modelData.type === "header" ? 48 : root.cellHeight

            // Section header — pill badge + horizontal rule
            RowLayout {
                visible: rowItem.modelData.type === "header"
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
                        text: rowItem.modelData.type === "header" ? (rowItem.modelData.letter ?? "") : ""
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
                        property var app: appCell.modelData
                        width: appList.width / root.columns
                        height: root.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 6
                            radius: Appearance.rounding.normal
                            color: appArea.containsMouse
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
                                source: Quickshell.iconPath(appCell.app?.icon ?? "", "image-missing")
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
