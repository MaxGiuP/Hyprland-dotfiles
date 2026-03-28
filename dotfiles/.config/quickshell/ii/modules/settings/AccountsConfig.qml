import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true
    baseWidth: 760

    ContentSection {
        icon: "account_circle"
        title: Translation.tr("Account")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("User-facing account actions are grouped here so you can jump straight into user management, password changes, and related system tools.")
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: profileRow.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            RowLayout {
                id: profileRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                MaterialSymbol {
                    text: "person"
                    iconSize: 34
                    color: Appearance.colors.colOnLayer1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: SystemInfo.username
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Medium
                    }

                    StyledText {
                        text: SystemInfo.distroName
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "manage_accounts"
        title: Translation.tr("Account tools")

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "manage_accounts"
                mainText: Translation.tr("Manage users")
                onClicked: Quickshell.execDetached(["bash", "-lc", Config.options.apps.manageUser])
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "password"
                mainText: Translation.tr("Change password")
                onClicked: Quickshell.execDetached(["bash", "-lc", Config.options.apps.changePassword])
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "terminal"
                mainText: Translation.tr("Open terminal")
                onClicked: Quickshell.execDetached(["bash", "-lc", Config.options.apps.terminal])
            }
        }
    }
}
