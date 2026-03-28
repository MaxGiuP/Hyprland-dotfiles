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

    ContentSection {
        icon: "settings"
        title: Translation.tr("Hypr Config Files")

        FileEditor {
            filePath: "/home/linmax/.config/hypr/hyprland/general.conf"
            title: Translation.tr("Core layout and input")
            placeholderText: Translation.tr("Hyprland general.conf")
        }

        FileEditor {
            filePath: "/home/linmax/.config/hypr/hyprland/keybinds.conf"
            title: Translation.tr("Main keybinds")
            placeholderText: Translation.tr("Hyprland keybinds.conf")
        }

        FileEditor {
            filePath: "/home/linmax/.config/hypr/hyprland/rules.conf"
            title: Translation.tr("Window rules")
            placeholderText: Translation.tr("Hyprland rules.conf")
        }

        FileEditor {
            filePath: "/home/linmax/.config/hypr/custom/general.conf"
            title: Translation.tr("Custom general overrides")
            placeholderText: Translation.tr("custom/general.conf")
        }

        FileEditor {
            filePath: "/home/linmax/.config/hypr/workspaces.conf"
            title: Translation.tr("Workspace bindings")
            placeholderText: Translation.tr("workspaces.conf")
        }

        FileEditor {
            filePath: "/home/linmax/.config/hypr/monitors.conf"
            title: Translation.tr("Monitor overrides")
            placeholderText: Translation.tr("monitors.conf")
        }
    }
}
