import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    readonly property string currentLang: {
        const full = Quickshell.env("LANG") ?? ""
        return full.replace(".UTF-8", "").replace(".utf8", "")
    }

    name: Translation.tr("Language")
    statusText: currentLang || Translation.tr("Unknown")
    tooltipText: Translation.tr("Language | Right-click to change")
    toggled: false
    icon: "language"
    mainAction: () => {}
    hasMenu: true
}
