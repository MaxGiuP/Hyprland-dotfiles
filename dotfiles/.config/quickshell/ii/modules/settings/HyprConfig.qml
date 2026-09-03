import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 860
    property int currentSubTab: 0
    readonly property string hyprConfigRoot: `${Quickshell.env("HOME")}/.config/hypr`
    readonly property var tabs: [
        { name: Translation.tr("General"), icon: "settings" },
        { name: Translation.tr("Input & workspaces"), icon: "keyboard" },
        { name: Translation.tr("Windows & displays"), icon: "select_window" },
        { name: Translation.tr("Startup"), icon: "rocket_launch" }
    ]

    function applySubTab(subTab, sectionId = "") {
        root.currentSubTab = Math.max(0, Math.min(subTab, root.tabs.length - 1))
        root.contentY = 0
    }

    component FileEditor: ColumnLayout {
        id: editorRoot
        required property string filePath
        required property string title
        required property string placeholderText

        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.leftMargin: 8
            color: Appearance.colors.colOnSecondaryContainer
            text: title
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 260
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            ScrollBar.horizontal.policy: ScrollBar.AsNeeded

            MaterialTextArea {
                id: editor
                anchors {
                    left: parent.left
                    right: parent.right
                }
                placeholderText: editorRoot.placeholderText
                wrapMode: TextEdit.NoWrap
                selectByMouse: true
                persistentSelection: true
            }
        }

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                text: editorRoot.filePath
                elide: Text.ElideLeft
            }

            RippleButtonWithIcon {
                materialIcon: "refresh"
                mainText: Translation.tr("Reload")
                onClicked: fileView.reload()
            }

            RippleButtonWithIcon {
                materialIcon: "save"
                mainText: Translation.tr("Save")
                onClicked: fileView.setText(editor.text)
            }
        }

        FileView {
            id: fileView
            path: editorRoot.filePath
            watchChanges: true

            onLoaded: {
                if (!editor.activeFocus)
                    editor.text = text();
            }

            onFileChanged: reload()

            onLoadFailed: error => {
                if (error === FileViewError.FileNotFound) {
                    editor.text = "";
                }
            }
        }
    }

    SecondaryTabBar {
        Layout.fillWidth: true
        currentIndex: root.currentSubTab
        onCurrentIndexChanged: {
            root.currentSubTab = currentIndex
            root.contentY = 0
        }

        Repeater {
            model: root.tabs
            delegate: SecondaryTabButton {
                required property var modelData
                buttonIcon: modelData.icon
                buttonText: modelData.name
            }
        }
    }

    ContentSection {
        icon: "settings"
        title: Translation.tr("Hypr Config Files")

        FileEditor {
            visible: root.currentSubTab === 0
            filePath: `${root.hyprConfigRoot}/hyprland/general.lua`
            title: Translation.tr("Core layout and input")
            placeholderText: Translation.tr("Hyprland general.lua")
        }

        FileEditor {
            visible: root.currentSubTab === 0
            filePath: `${root.hyprConfigRoot}/hyprland/env.lua`
            title: Translation.tr("Environment and locale")
            placeholderText: Translation.tr("Hyprland env.lua")
        }

        FileEditor {
            visible: root.currentSubTab === 3
            filePath: `${root.hyprConfigRoot}/hyprland/execs.lua`
            title: Translation.tr("Startup commands")
            placeholderText: Translation.tr("Hyprland execs.lua")
        }

        FileEditor {
            visible: root.currentSubTab === 1
            filePath: `${root.hyprConfigRoot}/hyprland/keybinds.lua`
            title: Translation.tr("Main keybinds")
            placeholderText: Translation.tr("Hyprland keybinds.lua")
        }

        FileEditor {
            visible: root.currentSubTab === 1
            filePath: `${root.hyprConfigRoot}/hyprland/keybinds.user.lua`
            title: Translation.tr("Additional keybinds (inactive)")
            placeholderText: Translation.tr("Hyprland keybinds.user.lua")
        }

        FileEditor {
            visible: root.currentSubTab === 2
            filePath: `${root.hyprConfigRoot}/hyprland/rules.lua`
            title: Translation.tr("Window rules")
            placeholderText: Translation.tr("Hyprland rules.lua")
        }

        FileEditor {
            visible: root.currentSubTab === 1
            filePath: `${root.hyprConfigRoot}/workspaces.lua`
            title: Translation.tr("Workspace bindings")
            placeholderText: Translation.tr("workspaces.lua")
        }

        FileEditor {
            visible: root.currentSubTab === 2
            filePath: `${root.hyprConfigRoot}/monitors.lua`
            title: Translation.tr("Monitor overrides")
            placeholderText: Translation.tr("monitors.lua")
        }
    }
}
