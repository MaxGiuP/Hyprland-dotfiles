import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentSection {
    component DesktopThemeOverviewCard: Rectangle {
        id: overviewCard
        required property string title
        required property string icon
        property string line1: ""
        property string line2: ""
        property string line3: ""

        Layout.fillWidth: true
        implicitHeight: 144
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: overviewCard.icon
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: overviewCard.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
            }

            StyledText {
                visible: text.length > 0
                text: overviewCard.line1
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.Wrap
            }
            StyledText {
                visible: text.length > 0
                text: overviewCard.line2
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
            StyledText {
                visible: text.length > 0
                text: overviewCard.line3
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }


        icon: "palette"
        title: Translation.tr("Desktop style hub")

        StyledText {
Layout.fillWidth: true
wrapMode: Text.Wrap
color: Appearance.colors.colSubtext
text: Translation.tr("Manage the theme stack that Quickshell sits on top of: GTK config files, GNOME interface settings, and KDE or Qt theme files from one place.")
        }

        RowLayout {
Layout.fillWidth: true
spacing: 10

DesktopThemeOverviewCard {
    title: Translation.tr("GTK")
    icon: "palette"
    line1: `${Translation.tr("GTK3")}: ${DesktopThemeSettings.gtk3Theme || "-"}`
    line2: `${Translation.tr("GTK4")}: ${DesktopThemeSettings.gtk4Theme || "-"}`
    line3: `${Translation.tr("Icons")}: ${DesktopThemeSettings.gtk4IconTheme || DesktopThemeSettings.gtk3IconTheme || "-"}`
}

DesktopThemeOverviewCard {
    title: Translation.tr("GNOME")
    icon: "deployed_code"
    line1: `${Translation.tr("Theme")}: ${DesktopThemeSettings.gnomeGtkTheme || "-"}`
    line2: `${Translation.tr("Color scheme")}: ${DesktopThemeSettings.gnomeColorScheme || "-"}`
    line3: `${Translation.tr("Font")}: ${DesktopThemeSettings.gnomeFont || "-"}`
}

DesktopThemeOverviewCard {
    title: Translation.tr("KDE / Qt")
    icon: "widgets"
    line1: `${Translation.tr("Colors")}: ${DesktopThemeSettings.kdeColorScheme || "-"}`
    line2: `${Translation.tr("Look and feel")}: ${DesktopThemeSettings.kdeLookAndFeel || "-"}`
    line3: `${Translation.tr("Kvantum")}: ${DesktopThemeSettings.kvantumTheme || "-"}`
}
        }

        ConfigRow {
uniform: true

RippleButtonWithIcon {
    Layout.fillWidth: true
    materialIcon: "edit_document"
    mainText: Translation.tr("GTK 3 file")
    onClicked: DesktopThemeSettings.openFile(DesktopThemeSettings.gtk3Path)
}

RippleButtonWithIcon {
    Layout.fillWidth: true
    materialIcon: "edit_document"
    mainText: Translation.tr("GTK 4 file")
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
    materialIcon: DesktopThemeSettings.scanning ? "progress_activity" : "refresh"
    mainText: DesktopThemeSettings.scanning ? Translation.tr("Refreshing values") : Translation.tr("Refresh values")
    enabled: !DesktopThemeSettings.scanning
    onClicked: DesktopThemeSettings.refreshAll()
}
        }
}
