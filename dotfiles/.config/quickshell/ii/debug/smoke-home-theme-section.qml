//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env II_STANDALONE_APP=1
//@ pragma Env II_SETTINGS_APP=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    visible: true
    width: 960
    height: 720
    title: "smoke-home-theme-section"
    color: Appearance.m3colors.m3background

    ContentPage {
        anchors.fill: parent
        forceWidth: true
        baseWidth: 760

        component SummaryCard: Rectangle {
            id: summaryCard
            required property string title
            required property string icon
            property string subtitle: ""
            property string detail: ""

            Layout.fillWidth: true
            implicitHeight: 118
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        text: summaryCard.icon
                        iconSize: 22
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: summaryCard.title
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                    }
                }

                StyledText {
                    text: summaryCard.subtitle
                    color: Appearance.colors.colOnLayer1
                    wrapMode: Text.Wrap
                }

                StyledText {
                    visible: text.length > 0
                    text: summaryCard.detail
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }
        }

        ContentSection {
            icon: "stylus"
            title: Translation.tr("Desktop theme stack")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("This settings app now exposes the theme layers below Quickshell as well, so you can see your GTK files, GNOME interface values, and KDE or Qt theme files in one place.")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                SummaryCard {
                    title: Translation.tr("GTK")
                    icon: "palette"
                    subtitle: `${DesktopThemeSettings.gtk4Theme || DesktopThemeSettings.gtk3Theme || "-"}`
                    detail: `${Translation.tr("Icons")}: ${DesktopThemeSettings.gtk4IconTheme || DesktopThemeSettings.gtk3IconTheme || "-"}`
                }

                SummaryCard {
                    title: Translation.tr("GNOME")
                    icon: "deployed_code"
                    subtitle: DesktopThemeSettings.gnomeGtkTheme || "-"
                    detail: `${Translation.tr("Scheme")}: ${DesktopThemeSettings.gnomeColorScheme || "-"}`
                }

                SummaryCard {
                    title: Translation.tr("KDE / Qt")
                    icon: "widgets"
                    subtitle: DesktopThemeSettings.kdeColorScheme || "-"
                    detail: `${Translation.tr("Kvantum")}: ${DesktopThemeSettings.kvantumTheme || "-"}`
                }
            }

            ConfigRow {
                uniform: true

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "edit_document"
                    mainText: Translation.tr("GTK files")
                    onClicked: DesktopThemeSettings.openFile(DesktopThemeSettings.gtk4Path)
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "edit_document"
                    mainText: Translation.tr("kdeglobals")
                    onClicked: DesktopThemeSettings.openFile(DesktopThemeSettings.kdeGlobalsPath)
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "refresh"
                    mainText: Translation.tr("Refresh system theme state")
                    onClicked: DesktopThemeSettings.refreshAll()
                }
            }
        }
    }
}
