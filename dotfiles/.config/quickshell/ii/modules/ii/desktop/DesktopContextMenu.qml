import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string desktopFsPath: ""
    property string targetFilePath: ""
    property string targetFileName: ""
    property bool targetIsDir: false
    property bool isFileMenu: false
    property int selectedCount: 0

    signal requestNameInput(string mode)
    signal renameRequested()
    signal refreshRequested()
    signal closeRequested()
    signal deleteRequested(string fpath)
    signal trashSelectedRequested()
    signal openSettingsRequested()

    visible: false
    implicitWidth: menuRect.width
    implicitHeight: menuRect.height

    Rectangle {
        id: menuRect
        width: 210
        height: menuColumn.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: Qt.rgba(Appearance.colors.colLayer1.r, Appearance.colors.colLayer1.g,
                       Appearance.colors.colLayer1.b, 1.0)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.45)
            shadowBlur: 0.25
            shadowVerticalOffset: 8
            shadowHorizontalOffset: 0
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
        }

        ColumnLayout {
            id: menuColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 8
                leftMargin: 8
                rightMargin: 8
            }
            spacing: 2

            // ── Background menu ────────────────────────────────────────────
            DesktopMenuButton {
                visible: !root.isFileMenu
                text: "New Text File"
                iconName: "document-new"
                onTriggered: { root.requestNameInput("file"); root.closeRequested() }
            }
            DesktopMenuButton {
                visible: !root.isFileMenu
                text: "New Folder"
                iconName: "folder-new"
                onTriggered: { root.requestNameInput("folder"); root.closeRequested() }
            }
            Rectangle {
                visible: !root.isFileMenu
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(1, 1, 1, 0.1)
            }
            DesktopMenuButton {
                visible: !root.isFileMenu
                text: "Refresh"
                iconName: "view-refresh"
                onTriggered: root.refreshRequested()
            }
            DesktopMenuButton {
                visible: !root.isFileMenu
                text: Translation.tr("Settings")
                iconName: "preferences-system"
                onTriggered: { root.openSettingsRequested(); root.closeRequested() }
            }
            // Bulk trash from background menu when items are selected
            Rectangle {
                visible: !root.isFileMenu && root.selectedCount > 0
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(1, 1, 1, 0.1)
            }
            DesktopMenuButton {
                visible: !root.isFileMenu && root.selectedCount > 0
                text: "Move " + root.selectedCount + " item" + (root.selectedCount === 1 ? "" : "s") + " to Trash"
                iconName: "user-trash"
                textColor: "#ef5350"
                onTriggered: { root.trashSelectedRequested(); root.closeRequested() }
            }

            // ── File/folder menu ───────────────────────────────────────────
            DesktopMenuButton {
                visible: root.isFileMenu
                text: Translation.tr("Open")
                iconName: "document-open"
                onTriggered: { openProcess.running = true; root.closeRequested() }
            }
            Rectangle {
                visible: root.isFileMenu
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(1, 1, 1, 0.1)
            }
            // Rename — only for a single selected item
            DesktopMenuButton {
                visible: root.isFileMenu && root.selectedCount <= 1
                text: "Rename"
                iconName: "edit-rename"
                onTriggered: { root.renameRequested(); root.closeRequested() }
            }
            Rectangle {
                visible: root.isFileMenu && root.selectedCount <= 1
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(1, 1, 1, 0.1)
            }
            // Single-item trash
            DesktopMenuButton {
                visible: root.isFileMenu && root.selectedCount <= 1
                text: "Move to Trash"
                iconName: "user-trash"
                textColor: "#ef5350"
                onTriggered: { root.deleteRequested(root.targetFilePath); root.closeRequested() }
            }
            // Bulk trash
            DesktopMenuButton {
                visible: root.isFileMenu && root.selectedCount > 1
                text: "Move " + root.selectedCount + " items to Trash"
                iconName: "user-trash"
                textColor: "#ef5350"
                onTriggered: { root.trashSelectedRequested(); root.closeRequested() }
            }
        }
    }

    Process {
        id: openProcess
        command: ["xdg-open", root.targetFilePath]
    }
}
