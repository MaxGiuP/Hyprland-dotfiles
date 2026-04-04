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
    readonly property real contentWidth: Math.max(
        newTextFileButton.visible ? newTextFileButton.implicitWidth : 0,
        newFolderButton.visible ? newFolderButton.implicitWidth : 0,
        refreshButton.visible ? refreshButton.implicitWidth : 0,
        settingsButton.visible ? settingsButton.implicitWidth : 0,
        trashSelectedButton.visible ? trashSelectedButton.implicitWidth : 0,
        openButton.visible ? openButton.implicitWidth : 0,
        renameButton.visible ? renameButton.implicitWidth : 0,
        singleTrashButton.visible ? singleTrashButton.implicitWidth : 0,
        bulkTrashButton.visible ? bulkTrashButton.implicitWidth : 0
    )
    implicitWidth: menuRect.width
    implicitHeight: menuRect.height

    Rectangle {
        id: menuRect
        width: root.contentWidth + 16
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
                id: newTextFileButton
                visible: !root.isFileMenu
                text: Translation.tr("New Text File")
                iconName: "document-new"
                onTriggered: { root.requestNameInput("file"); root.closeRequested() }
            }
            DesktopMenuButton {
                id: newFolderButton
                visible: !root.isFileMenu
                text: Translation.tr("New Folder")
                iconName: "folder-new"
                onTriggered: { root.requestNameInput("folder"); root.closeRequested() }
            }
            Rectangle {
                visible: !root.isFileMenu
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(1, 1, 1, 0.1)
            }
            DesktopMenuButton {
                id: refreshButton
                visible: !root.isFileMenu
                text: Translation.tr("Refresh")
                iconName: "view-refresh"
                onTriggered: root.refreshRequested()
            }
            DesktopMenuButton {
                id: settingsButton
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
                id: trashSelectedButton
                visible: !root.isFileMenu && root.selectedCount > 0
                text: root.selectedCount === 1
                    ? Translation.tr("Move %1 item to Trash").arg(root.selectedCount)
                    : Translation.tr("Move %1 items to Trash").arg(root.selectedCount)
                iconName: "user-trash"
                textColor: "#ef5350"
                onTriggered: { root.trashSelectedRequested(); root.closeRequested() }
            }

            // ── File/folder menu ───────────────────────────────────────────
            DesktopMenuButton {
                id: openButton
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
                id: renameButton
                visible: root.isFileMenu && root.selectedCount <= 1
                text: Translation.tr("Rename")
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
                id: singleTrashButton
                visible: root.isFileMenu && root.selectedCount <= 1
                text: Translation.tr("Move to Trash")
                iconName: "user-trash"
                textColor: "#ef5350"
                onTriggered: { root.deleteRequested(root.targetFilePath); root.closeRequested() }
            }
            // Bulk trash
            DesktopMenuButton {
                id: bulkTrashButton
                visible: root.isFileMenu && root.selectedCount > 1
                text: Translation.tr("Move %1 items to Trash").arg(root.selectedCount)
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
