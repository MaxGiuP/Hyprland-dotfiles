pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property bool settingsApp: Quickshell.env("II_SETTINGS_APP") === "1"

    readonly property string gtk3Path: `${Quickshell.env("HOME")}/.config/gtk-3.0/settings.ini`
    readonly property string gtk4Path: `${Quickshell.env("HOME")}/.config/gtk-4.0/settings.ini`
    readonly property string kdeGlobalsPath: `${Quickshell.env("HOME")}/.config/kdeglobals`
    readonly property string kvantumPath: `${Quickshell.env("HOME")}/.config/Kvantum/kvantum.kvconfig`
    readonly property var kdeStoreOptions: [
        {
            displayName: "Global themes",
            description: "Download Plasma look-and-feel bundles from the KDE Store.",
            knsrc: "/usr/share/knsrcfiles/lookandfeel.knsrc"
        },
        {
            displayName: "Icon themes",
            description: "Browse icon packs and apply them after install.",
            knsrc: "/usr/share/knsrcfiles/icons.knsrc"
        },
        {
            displayName: "Cursor themes",
            description: "Install pointer themes from KDE's KNewStuff catalog.",
            knsrc: "/usr/share/knsrcfiles/xcursor.knsrc"
        },
        {
            displayName: "Color schemes",
            description: "Get additional KDE color schemes.",
            knsrc: "/usr/share/knsrcfiles/colorschemes.knsrc"
        },
        {
            displayName: "GTK themes",
            description: "Download GNOME and GTK application styles.",
            knsrc: "/usr/share/knsrcfiles/gtk_themes.knsrc"
        },
        {
            displayName: "Window decorations",
            description: "Install Aurorae and other KDE decoration packs.",
            knsrc: "/usr/share/knsrcfiles/window-decorations.knsrc"
        }
    ]

    property var gtkThemeOptions: []
    property var iconThemeOptions: []
    property var cursorThemeOptions: []
    property var kdeColorSchemeOptions: []
    property var kdeLookAndFeelOptions: []
    property var kvantumThemeOptions: []
    readonly property var defaultFontFamilyValues: [
        "Sans Serif",
        "Serif",
        "Monospace",
        "Noto Sans",
        "Noto Sans Display",
        "Noto Serif",
        "Noto Sans Mono",
        "Cantarell",
        "Inter",
        "Roboto",
        "Ubuntu",
        "Fira Sans",
        "Fira Code",
        "JetBrains Mono",
        "Iosevka",
        "IBM Plex Sans",
        "IBM Plex Serif",
        "IBM Plex Mono",
        "Source Sans 3",
        "Source Serif 4",
        "DejaVu Sans",
        "DejaVu Serif",
        "Liberation Sans",
        "Liberation Serif",
        "Hack"
    ]
    property var fontFamilyOptions: toOptionList(defaultFontFamilyValues)
    readonly property var fontWeightOptions: [
        { displayName: "Thin", value: "Thin" },
        { displayName: "ExtraLight", value: "ExtraLight" },
        { displayName: "Light", value: "Light" },
        { displayName: "Regular", value: "Regular" },
        { displayName: "Medium", value: "Medium" },
        { displayName: "SemiBold", value: "SemiBold" },
        { displayName: "Bold", value: "Bold" },
        { displayName: "ExtraBold", value: "ExtraBold" },
        { displayName: "Black", value: "Black" }
    ]
    readonly property var fontSizeOptions: [
        { displayName: "9 px", value: "9" },
        { displayName: "10 px", value: "10" },
        { displayName: "11 px", value: "11" },
        { displayName: "12 px", value: "12" },
        { displayName: "13 px", value: "13" },
        { displayName: "14 px", value: "14" },
        { displayName: "16 px", value: "16" },
        { displayName: "18 px", value: "18" },
        { displayName: "20 px", value: "20" },
        { displayName: "24 px", value: "24" },
        { displayName: "28 px", value: "28" },
        { displayName: "32 px", value: "32" }
    ]

    property string gtk3Theme: ""
    property string gtk3IconTheme: ""
    property string gtk3CursorTheme: ""
    property string gtk3Font: ""
    property int gtk3CursorSize: 24
    property bool gtk3PreferDark: false

    property string gtk4Theme: ""
    property string gtk4IconTheme: ""
    property string gtk4CursorTheme: ""
    property string gtk4Font: ""
    property int gtk4CursorSize: 24
    property bool gtk4PreferDark: false

    property string gnomeGtkTheme: ""
    property string gnomeIconTheme: ""
    property string gnomeCursorTheme: ""
    property string gnomeFont: ""
    property string gnomeColorScheme: ""
    property int gnomeCursorSize: 24
    property real gnomeTextScaling: 1.0
    property bool gnomeAnimations: true
    property bool gnomeHotCorners: true
    property bool gnomeShowBatteryPercentage: false
    property string gnomeClockFormat: "24h"

    property string kdeColorScheme: ""
    property string kdeIconTheme: ""
    property string kdeLookAndFeel: ""
    property string kdeFont: ""
    property string kvantumTheme: ""
    property bool kdeAutomaticLookAndFeel: false
    property bool kdeShowDeleteCommand: false

    function parseIniValue(content, section, key, fallback = "") {
        const lines = (content || "").replace(/\r/g, "").split("\n");
        let currentSection = "";
        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
                currentSection = trimmed.slice(1, -1);
                continue;
            }
            if (currentSection !== section) continue;
            if (trimmed.startsWith(`${key}=`)) return trimmed.slice(key.length + 1);
        }
        return fallback;
    }

    function setIniValue(content, section, key, value) {
        const lines = (content || "").replace(/\r/g, "").split("\n");
        const sectionHeader = `[${section}]`;
        let sectionStart = -1;
        let sectionEnd = lines.length;

        for (let i = 0; i < lines.length; i++) {
            const trimmed = lines[i].trim();
            if (trimmed === sectionHeader) {
                sectionStart = i;
                for (let j = i + 1; j < lines.length; j++) {
                    const next = lines[j].trim();
                    if (next.startsWith("[") && next.endsWith("]")) {
                        sectionEnd = j;
                        break;
                    }
                }
                break;
            }
        }

        if (sectionStart === -1) {
            if (lines.length > 0 && lines[lines.length - 1] !== "") lines.push("");
            lines.push(sectionHeader);
            lines.push(`${key}=${value}`);
            return lines.join("\n");
        }

        for (let i = sectionStart + 1; i < sectionEnd; i++) {
            const trimmed = lines[i].trim();
            if (trimmed.startsWith(`${key}=`)) {
                lines[i] = `${key}=${value}`;
                return lines.join("\n");
            }
        }

        lines.splice(sectionEnd, 0, `${key}=${value}`);
        return lines.join("\n");
    }

    function refreshAll() {
        gtk3View.reload();
        gtk4View.reload();
        kdeGlobalsView.reload();
        kvantumView.reload();
        themeScanner.running = false;
        iconScanner.running = false;
        colorSchemeScanner.running = false;
        lookAndFeelScanner.running = false;
        kvantumScanner.running = false;
        fontScanner.running = false;
        gtkThemeOptions = [];
        iconThemeOptions = [];
        cursorThemeOptions = [];
        kdeColorSchemeOptions = [];
        kdeLookAndFeelOptions = [];
        kvantumThemeOptions = [];
        fontFamilyOptions = toOptionList(defaultFontFamilyValues);
        if (root.settingsApp) {
            themeScanner.running = true;
            iconScanner.running = true;
            colorSchemeScanner.running = true;
            lookAndFeelScanner.running = true;
            kvantumScanner.running = true;
            fontScanner.running = true;
            gnomeRefresh.running = false;
            gnomeRefresh.running = true;
        }
    }

    function toOptionList(values) {
        return [...new Set(values.filter(v => v && v.length > 0))].map(v => ({
            displayName: v,
            value: v
        }));
    }

    function saveGtk3(values) {
        let content = gtk3View.text() || "[Settings]\n";
        content = setIniValue(content, "Settings", "gtk-theme-name", values.theme);
        content = setIniValue(content, "Settings", "gtk-icon-theme-name", values.iconTheme);
        content = setIniValue(content, "Settings", "gtk-cursor-theme-name", values.cursorTheme);
        content = setIniValue(content, "Settings", "gtk-font-name", buildGtkFont(values.fontFamily, values.fontWeight, values.fontSize));
        content = setIniValue(content, "Settings", "gtk-cursor-theme-size", `${values.cursorSize}`);
        content = setIniValue(content, "Settings", "gtk-application-prefer-dark-theme", values.preferDark ? "1" : "0");
        gtk3View.setText(content);
        gtk3View.reload();
    }

    function saveGtk4(values) {
        let content = gtk4View.text() || "[Settings]\n";
        content = setIniValue(content, "Settings", "gtk-theme-name", values.theme);
        content = setIniValue(content, "Settings", "gtk-icon-theme-name", values.iconTheme);
        content = setIniValue(content, "Settings", "gtk-cursor-theme-name", values.cursorTheme);
        content = setIniValue(content, "Settings", "gtk-font-name", buildGtkFont(values.fontFamily, values.fontWeight, values.fontSize));
        content = setIniValue(content, "Settings", "gtk-cursor-theme-size", `${values.cursorSize}`);
        content = setIniValue(content, "Settings", "gtk-application-prefer-dark-theme", values.preferDark ? "1" : "0");
        gtk4View.setText(content);
        gtk4View.reload();
    }

    function saveKde(values) {
        let content = kdeGlobalsView.text() || "";
        content = setIniValue(content, "General", "ColorScheme", values.colorScheme);
        content = setIniValue(content, "General", "font", buildKdeFont(kdeFont, values.fontFamily, values.fontWeight, values.fontSize));
        content = setIniValue(content, "Icons", "Theme", values.iconTheme);
        content = setIniValue(content, "KDE", "LookAndFeelPackage", values.lookAndFeel);
        kdeGlobalsView.setText(content);
        kdeGlobalsView.reload();
    }

    function saveKvantumTheme(theme) {
        let content = kvantumView.text() || "";
        content = setIniValue(content, "General", "theme", theme);
        kvantumView.setText(content);
        kvantumView.reload();
    }

    function applyGnome(values) {
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", values.gtkTheme]);
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", values.iconTheme]);
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", values.cursorTheme]);
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "font-name", buildGtkFont(values.fontFamily, values.fontWeight, values.fontSize)]);
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", values.colorScheme]);
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", `${values.cursorSize}`]);
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "text-scaling-factor", `${values.textScaling}`]);
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "enable-animations", values.animations ? "true" : "false"]);
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "enable-hot-corners", values.hotCorners ? "true" : "false"]);
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "show-battery-percentage", values.showBatteryPercentage ? "true" : "false"]);
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "clock-format", values.clockFormat]);

        root.gnomeGtkTheme = values.gtkTheme;
        root.gnomeIconTheme = values.iconTheme;
        root.gnomeCursorTheme = values.cursorTheme;
        root.gnomeFont = buildGtkFont(values.fontFamily, values.fontWeight, values.fontSize);
        root.gnomeColorScheme = values.colorScheme;
        root.gnomeCursorSize = values.cursorSize;
        root.gnomeTextScaling = values.textScaling;
        root.gnomeAnimations = values.animations;
        root.gnomeHotCorners = values.hotCorners;
        root.gnomeShowBatteryPercentage = values.showBatteryPercentage;
        root.gnomeClockFormat = values.clockFormat;
    }

    function saveKdeToggles(values) {
        let content = kdeGlobalsView.text() || "";
        content = setIniValue(content, "KDE", "AutomaticLookAndFeel", values.automaticLookAndFeel ? "true" : "false");
        content = setIniValue(content, "KDE", "ShowDeleteCommand", values.showDeleteCommand ? "true" : "false");
        kdeGlobalsView.setText(content);
        kdeGlobalsView.reload();
        root.kdeAutomaticLookAndFeel = values.automaticLookAndFeel;
        root.kdeShowDeleteCommand = values.showDeleteCommand;
    }

    function parseGtkFontFamily(font) {
        const raw = (font || "").trim();
        if (raw.length === 0) return "";
        const stripped = raw.replace(/\s*@.*$/, "").replace(/\s+\d+$/, "");
        for (const weight of [" Black", " ExtraBold", " ExtraLight", " SemiBold", " Medium", " Bold", " Light", " Thin", " Regular"]) {
            if (stripped.endsWith(weight)) return stripped.slice(0, -weight.length);
        }
        return stripped;
    }

    function parseGtkFontWeight(font) {
        const raw = (font || "").trim();
        for (const weight of ["Black", "ExtraBold", "ExtraLight", "SemiBold", "Medium", "Bold", "Light", "Thin", "Regular"]) {
            if (raw.includes(weight)) return weight;
        }
        return "Regular";
    }

    function parseGtkFontSize(font) {
        const match = (font || "").match(/ (\d+)(?:\s*@.*)?$/);
        return match ? Number(match[1]) : 11;
    }

    function buildGtkFont(family, weight, size) {
        const parts = [family];
        if (weight && weight !== "Regular") parts.push(weight);
        parts.push(`${size}`);
        return parts.join(" ").trim();
    }

    function parseKdeFontFamily(font) {
        return ((font || "").split(",")[0] || "").trim();
    }

    function parseKdeFontSize(font) {
        const size = Number(((font || "").split(",")[1] || "11").trim());
        return Number.isFinite(size) ? size : 11;
    }

    function parseKdeFontWeight(font) {
        const parts = (font || "").split(",");
        const weight = Number((parts[4] || "400").trim());
        if (weight >= 850) return "Black";
        if (weight >= 750) return "ExtraBold";
        if (weight >= 700) return "Bold";
        if (weight >= 600) return "SemiBold";
        if (weight >= 500) return "Medium";
        if (weight <= 200) return "ExtraLight";
        if (weight <= 250) return "Thin";
        if (weight <= 300) return "Light";
        return "Regular";
    }

    function kdeWeightValue(weight) {
        switch (weight) {
            case "Thin": return "100";
            case "ExtraLight": return "200";
            case "Light": return "300";
            case "Medium": return "500";
            case "SemiBold": return "600";
            case "Bold": return "700";
            case "ExtraBold": return "800";
            case "Black": return "900";
            default: return "400";
        }
    }

    function buildKdeFont(existing, family, weight, size) {
        const parts = (existing || "Sans Serif,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1").split(",");
        while (parts.length < 16) parts.push("0");
        parts[0] = family;
        parts[1] = `${size}`;
        parts[4] = kdeWeightValue(weight);
        return parts.join(",");
    }

    function openFile(path) {
        Qt.openUrlExternally(`file://${path}`);
    }

    function openKdeStore(knsrcPath) {
        Quickshell.execDetached(["knewstuff-dialog6", knsrcPath]);
    }

    function openSystemSettings() {
        Quickshell.execDetached(["systemsettings"]);
    }

    FileView {
        id: gtk3View
        path: root.gtk3Path
        watchChanges: true
        onLoadedChanged: {
            const content = gtk3View.text();
            root.gtk3Theme = root.parseIniValue(content, "Settings", "gtk-theme-name");
            root.gtk3IconTheme = root.parseIniValue(content, "Settings", "gtk-icon-theme-name");
            root.gtk3CursorTheme = root.parseIniValue(content, "Settings", "gtk-cursor-theme-name");
            root.gtk3Font = root.parseIniValue(content, "Settings", "gtk-font-name");
            root.gtk3CursorSize = Number(root.parseIniValue(content, "Settings", "gtk-cursor-theme-size", "24"));
            root.gtk3PreferDark = root.parseIniValue(content, "Settings", "gtk-application-prefer-dark-theme", "0") === "1";
        }
        onFileChanged: reload()
    }

    FileView {
        id: gtk4View
        path: root.gtk4Path
        watchChanges: true
        onLoadedChanged: {
            const content = gtk4View.text();
            root.gtk4Theme = root.parseIniValue(content, "Settings", "gtk-theme-name");
            root.gtk4IconTheme = root.parseIniValue(content, "Settings", "gtk-icon-theme-name");
            root.gtk4CursorTheme = root.parseIniValue(content, "Settings", "gtk-cursor-theme-name");
            root.gtk4Font = root.parseIniValue(content, "Settings", "gtk-font-name");
            root.gtk4CursorSize = Number(root.parseIniValue(content, "Settings", "gtk-cursor-theme-size", "24"));
            root.gtk4PreferDark = root.parseIniValue(content, "Settings", "gtk-application-prefer-dark-theme", "0") === "1";
        }
        onFileChanged: reload()
    }

    FileView {
        id: kdeGlobalsView
        path: root.kdeGlobalsPath
        watchChanges: true
        onLoadedChanged: {
            const content = kdeGlobalsView.text();
            root.kdeColorScheme = root.parseIniValue(content, "General", "ColorScheme");
            root.kdeFont = root.parseIniValue(content, "General", "font");
            root.kdeIconTheme = root.parseIniValue(content, "Icons", "Theme");
            root.kdeLookAndFeel = root.parseIniValue(content, "KDE", "LookAndFeelPackage");
            root.kdeAutomaticLookAndFeel = root.parseIniValue(content, "KDE", "AutomaticLookAndFeel", "false") === "true";
            root.kdeShowDeleteCommand = root.parseIniValue(content, "KDE", "ShowDeleteCommand", "false") === "true";
        }
        onFileChanged: reload()
    }

    FileView {
        id: kvantumView
        path: root.kvantumPath
        watchChanges: true
        onLoadedChanged: {
            const content = kvantumView.text();
            root.kvantumTheme = root.parseIniValue(content, "General", "theme");
        }
        onFileChanged: reload()
    }

    Process {
        id: gnomeRefresh
        running: root.settingsApp
        command: ["bash", "-lc",
            "printf 'gtk-theme:%s\n' \"$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d \"'\\\"\")\"; " +
            "printf 'icon-theme:%s\n' \"$(gsettings get org.gnome.desktop.interface icon-theme | tr -d \"'\\\"\")\"; " +
            "printf 'cursor-theme:%s\n' \"$(gsettings get org.gnome.desktop.interface cursor-theme | tr -d \"'\\\"\")\"; " +
            "printf 'font-name:%s\n' \"$(gsettings get org.gnome.desktop.interface font-name | tr -d \"'\\\"\")\"; " +
            "printf 'color-scheme:%s\n' \"$(gsettings get org.gnome.desktop.interface color-scheme | tr -d \"'\\\"\")\"; " +
            "printf 'cursor-size:%s\n' \"$(gsettings get org.gnome.desktop.interface cursor-size | tr -d \"'\\\"\")\"; " +
            "printf 'text-scaling-factor:%s\n' \"$(gsettings get org.gnome.desktop.interface text-scaling-factor | tr -d \"'\\\"\")\"; " +
            "printf 'enable-animations:%s\n' \"$(gsettings get org.gnome.desktop.interface enable-animations | tr -d \"'\\\"\")\"; " +
            "printf 'enable-hot-corners:%s\n' \"$(gsettings get org.gnome.desktop.interface enable-hot-corners | tr -d \"'\\\"\")\"; " +
            "printf 'show-battery-percentage:%s\n' \"$(gsettings get org.gnome.desktop.interface show-battery-percentage | tr -d \"'\\\"\")\"; " +
            "printf 'clock-format:%s\n' \"$(gsettings get org.gnome.desktop.interface clock-format | tr -d \"'\\\"\")\""
        ]
        stdout: SplitParser {
            onRead: data => {
                const idx = data.indexOf(":");
                if (idx < 0) return;
                const key = data.slice(0, idx);
                const value = data.slice(idx + 1);
                switch (key) {
                    case "gtk-theme": root.gnomeGtkTheme = value; break;
                    case "icon-theme": root.gnomeIconTheme = value; break;
                    case "cursor-theme": root.gnomeCursorTheme = value; break;
                    case "font-name": root.gnomeFont = value; break;
                    case "color-scheme": root.gnomeColorScheme = value; break;
                    case "cursor-size": root.gnomeCursorSize = Number(value); break;
                    case "text-scaling-factor": root.gnomeTextScaling = Number(value); break;
                    case "enable-animations": root.gnomeAnimations = value === "true"; break;
                    case "enable-hot-corners": root.gnomeHotCorners = value === "true"; break;
                    case "show-battery-percentage": root.gnomeShowBatteryPercentage = value === "true"; break;
                    case "clock-format": root.gnomeClockFormat = value; break;
                }
            }
        }
    }

    Process {
        id: themeScanner
        running: root.settingsApp
        command: ["bash", "-lc", "find /usr/share/themes ~/.themes -maxdepth 1 -mindepth 1 -type d 2>/dev/null | xargs -r -n1 basename | sort -u"]
        stdout: SplitParser {
            onRead: data => {
                const next = [...root.gtkThemeOptions.map(item => item.value), data];
                root.gtkThemeOptions = root.toOptionList(next);
            }
        }
    }

    Process {
        id: iconScanner
        running: root.settingsApp
        command: ["bash", "-lc", "find /usr/share/icons ~/.icons -maxdepth 1 -mindepth 1 -type d 2>/dev/null | xargs -r -n1 basename | sort -u"]
        stdout: SplitParser {
            onRead: data => {
                const next = [...root.iconThemeOptions.map(item => item.value), data];
                const options = root.toOptionList(next);
                root.iconThemeOptions = options;
                root.cursorThemeOptions = options;
            }
        }
    }

    Process {
        id: colorSchemeScanner
        running: root.settingsApp
        command: ["bash", "-lc", "find /usr/share/color-schemes ~/.local/share/color-schemes -maxdepth 1 -mindepth 1 \\( -name '*.colors' -o -type d \\) 2>/dev/null | sed 's#.*/##' | sed 's/\\.colors$//' | sort -u"]
        stdout: SplitParser {
            onRead: data => {
                const next = [...root.kdeColorSchemeOptions.map(item => item.value), data];
                root.kdeColorSchemeOptions = root.toOptionList(next);
            }
        }
    }

    Process {
        id: lookAndFeelScanner
        running: root.settingsApp
        command: ["bash", "-lc", "find /usr/share/plasma/look-and-feel ~/.local/share/plasma/look-and-feel -maxdepth 1 -mindepth 1 -type d 2>/dev/null | xargs -r -n1 basename | sort -u"]
        stdout: SplitParser {
            onRead: data => {
                const next = [...root.kdeLookAndFeelOptions.map(item => item.value), data];
                root.kdeLookAndFeelOptions = root.toOptionList(next);
            }
        }
    }

    Process {
        id: kvantumScanner
        running: root.settingsApp
        command: ["bash", "-lc", "find /usr/share/Kvantum ~/.config/Kvantum -maxdepth 1 -mindepth 1 -type d 2>/dev/null | xargs -r -n1 basename | sort -u"]
        stdout: SplitParser {
            onRead: data => {
                const next = [...root.kvantumThemeOptions.map(item => item.value), data];
                root.kvantumThemeOptions = root.toOptionList(next);
            }
        }
    }

    Process {
        id: fontScanner
        running: root.settingsApp
        command: ["bash", "-lc", "fc-list : family | sed 's/,/\\n/g' | sed 's/^ *//;s/ *$//' | awk 'NF' | sort -u"]
        stdout: SplitParser {
            onRead: data => {
                const next = [...root.defaultFontFamilyValues, ...root.fontFamilyOptions.map(item => item.value), data];
                root.fontFamilyOptions = root.toOptionList(next);
            }
        }
    }
}
