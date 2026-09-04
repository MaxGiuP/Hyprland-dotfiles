pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import qs.modules.common
import qs.services

Singleton {
    id: root
    
    readonly property list<var> availableWidgets: [
        { identifier: "crosshair", materialSymbol: "point_scan" },
        { identifier: "fpsLimiter", materialSymbol: "animation" },
        { identifier: "floatingImage", materialSymbol: "imagesmode" },
        { identifier: "recorder", materialSymbol: "screen_record" },
        { identifier: "resources", materialSymbol: "browse_activity" },
        { identifier: "notes", materialSymbol: "note_stack" },
        { identifier: "volumeMixer", materialSymbol: "volume_up" },
        { identifier: "liveCaptions", materialSymbol: "subtitles" },
        { identifier: "liveCaptionsTranslation", materialSymbol: "translate" },
        { identifier: "liveScreenTranslation", materialSymbol: "text_snippet" },
        { identifier: "liveScreenTranslationOutput", materialSymbol: "language" },
        { identifier: "liveCaptionsSettings", materialSymbol: "settings_voice" },
        { identifier: "settingsMenu", materialSymbol: "settings" },
        { identifier: "terminal", materialSymbol: "terminal" },
        { identifier: "calculator", materialSymbol: "calculate", displayName: Translation.tr("Calculator"), group: "systemApps" },
        { identifier: "timers", materialSymbol: "timer", displayName: Translation.tr("Timers"), group: "systemApps" },
        { identifier: "systemDashboard", materialSymbol: "space_dashboard", displayName: Translation.tr("System Dashboard"), group: "systemApps" },
    ]
    
    readonly property list<string> persistedPinnedWidgetIdentifiers: {
        if (!Persistent.ready)
            return []
        const openWidgets = Persistent.states.overlay.open ?? []
        return openWidgets.filter(identifier => Persistent.states.overlay[identifier]?.pinned ?? false)
    }
    readonly property bool hasPinnedWidgets: root.persistedPinnedWidgetIdentifiers.length > 0
        || root.pinnedWidgetIdentifiers.length > 0

    property list<string> pinnedWidgetIdentifiers: []
    property list<var> clickableWidgets: []

    function pin(identifier: string, pin = true) {
        if (pin) {
            if (!root.pinnedWidgetIdentifiers.includes(identifier)) {
                root.pinnedWidgetIdentifiers = root.pinnedWidgetIdentifiers.concat([identifier])
            }
        } else {
            root.pinnedWidgetIdentifiers = root.pinnedWidgetIdentifiers.filter(id => id !== identifier)
        }
    }

    function registerClickableWidget(widget: var, clickable = true) {
        if (clickable) {
            if (!root.clickableWidgets.includes(widget)) {
                root.clickableWidgets.push(widget)
            }
        } else {
            root.clickableWidgets = root.clickableWidgets.filter(w => w !== widget)
        }
    }
}
