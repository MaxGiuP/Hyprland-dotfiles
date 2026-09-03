import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ContentSection {
        icon: "storefront"
        title: Translation.tr("KDE Store")

        StyledText {
Layout.fillWidth: true
wrapMode: Text.Wrap
color: Appearance.colors.colSubtext
text: Translation.tr("Open KDE's KNewStuff catalogs directly from here to download new global themes, icons, cursors, color schemes, GTK themes, and window decorations.")
        }

        Flow {
Layout.fillWidth: true
spacing: 8

Repeater {
    model: DesktopThemeSettings.kdeStoreOptions

    delegate: RippleButtonWithIcon {
        required property var modelData
        materialIcon: "download"
        mainText: modelData.displayName
        mainContentComponent: Component {
            ColumnLayout {
                spacing: 1

                StyledText {
                    text: modelData.displayName
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSecondaryContainer
                }

                StyledText {
                    text: modelData.description
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSecondaryContainer
                    opacity: 0.75
                    wrapMode: Text.Wrap
                }
            }
        }
        onClicked: DesktopThemeSettings.openKdeStore(modelData.knsrc)
    }
}
        }

        ConfigRow {
uniform: true

RippleButtonWithIcon {
    Layout.fillWidth: true
    materialIcon: "palette"
    mainText: Translation.tr("Open appearance settings")
    onClicked: DesktopThemeSettings.openSystemSettings()
}

RippleButtonWithIcon {
    Layout.fillWidth: true
    materialIcon: "edit_document"
    mainText: Translation.tr("Open kdeglobals")
    onClicked: DesktopThemeSettings.openFile(DesktopThemeSettings.kdeGlobalsPath)
}
        }
}
