import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true
    baseWidth: 760

    ContentSection {
        icon: "home"
        title: Translation.tr("Home")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnLayer1
            text: Translation.tr("Use the sidebar to open each settings category. The standalone settings window uses a simplified home page so it can launch reliably outside the full shell session.")
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Display, audio, connectivity, theme, language, accessibility, privacy, services, and Hyprland settings are still available from the navigation panel on the left.")
        }
    }

    ContentSection {
        icon: "info"
        title: Translation.tr("Tips")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("If you are looking for the quick dashboard widgets from the main shell home page, open the shell-integrated settings view instead of the standalone app.")
        }
    }
}
