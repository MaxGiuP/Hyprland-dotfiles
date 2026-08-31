import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
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
        icon: "hub"
        title: Translation.tr("Connected accounts")
        description: Translation.tr("Thunderbird securely owns account credentials; Quickshell reads only calendar and indexed mail metadata.")

        Repeater {
            model: UnifiedAgenda.accounts

            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: accountRow.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                RowLayout {
                    id: accountRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Rectangle {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSecondaryContainer
                        MaterialSymbol { anchors.centerIn: parent; text: modelData.provider === "Gmail" ? "mail" : "alternate_email"; iconSize: 20; color: Appearance.colors.colOnSecondaryContainer }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText { Layout.fillWidth: true; text: modelData.address; color: Appearance.colors.colOnLayer1; font.weight: Font.Medium; elide: Text.ElideRight }
                        StyledText { text: `${modelData.provider} • ${modelData.protocol}`; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small }
                    }

                    StyledText {
                        text: Translation.tr("%1 unread").arg(modelData.unread)
                        color: modelData.unread > 0 ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        font.weight: modelData.unread > 0 ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }

        StyledText {
            visible: UnifiedAgenda.accounts.length === 0
            Layout.fillWidth: true
            text: UnifiedAgenda.mailError || Translation.tr("No Thunderbird mail accounts were found.")
            color: UnifiedAgenda.mailError ? Appearance.colors.colError : Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: calendarStatusRow.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            RowLayout {
                id: calendarStatusRow
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10
                MaterialSymbol { text: RemoteCalendarBridge.lastError ? "event_busy" : "event_available"; iconSize: 22; color: RemoteCalendarBridge.lastError ? Appearance.colors.colError : Appearance.colors.colPrimary }
                ColumnLayout {
                    Layout.fillWidth: true
                    StyledText { text: Translation.tr("Calendar and tasks"); color: Appearance.colors.colOnLayer1; font.weight: Font.Medium }
                    StyledText { Layout.fillWidth: true; text: RemoteCalendarBridge.lastError || Translation.tr("%1 events and %2 remote tasks synced").arg(RemoteCalendarBridge.thunderbirdEvents.length).arg(RemoteCalendarBridge.thunderbirdTasks.length); color: RemoteCalendarBridge.lastError ? Appearance.colors.colError : Appearance.colors.colSubtext; wrapMode: Text.Wrap }
                }
            }
        }

        ConfigRow {
            uniform: true
            RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "refresh"; mainText: Translation.tr("Refresh accounts"); onClicked: UnifiedAgenda.refresh() }
            RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "add_link"; mainText: Translation.tr("Add or manage accounts"); onClicked: UnifiedAgenda.openAccountSettings() }
            RippleButtonWithIcon { Layout.fillWidth: true; materialIcon: "mail"; mainText: Translation.tr("Open Thunderbird"); onClicked: UnifiedAgenda.openMail() }
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Add Gmail, Microsoft, IMAP, CalDAV or ICS accounts in Thunderbird and they will appear here automatically after refresh.")
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
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
