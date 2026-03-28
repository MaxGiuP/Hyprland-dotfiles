pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    function normalizeText(value) {
        return String(value ?? "")
            .trim()
            .toLowerCase()
            .replace(/\s+/g, " ");
    }

    function normalizedCommand(app) {
        const command = Array.from(app?.command ?? []).map(part => String(part ?? "").trim()).filter(Boolean);
        if (command.length > 0) return command.join(" ");
        return normalizeText(app?.execString ?? "");
    }

    function iconPriority(iconName) {
        if (!iconExists(iconName)) return 0;

        const resolvedPath = Quickshell.iconPath(iconName, true);
        const genericNames = [
            "application-x-executable",
            "application-default-icon",
            "application-octet-stream",
            "application-x-desktop",
            "image-missing"
        ];

        if (genericNames.indexOf(iconName) !== -1) return 0;
        if (genericNames.some(name => resolvedPath.indexOf(`/${name}`) !== -1)) return 0;
        if (resolvedPath.indexOf("/hicolor/") !== -1) return 1;
        return 2;
    }

    function shouldShowApp(app) {
        if (!app) return false;
        if (app.noDisplay) return false;
        if (app.runInTerminal) return false;
        const normalizedName = normalizeText(app.name);
        if (normalizedName.length === 0) return false;
        const command = normalizedCommand(app);
        if (command.length === 0) return false;

        const categories = Array.from(app?.categories ?? []).map(category => String(category ?? "").trim()).filter(Boolean);
        const hasOnlyToolCategories = categories.length > 0 && categories.every(category => /(?:^|-)tools$/i.test(category));
        const appId = String(app?.id ?? "");
        const iconScore = iconPriority(app?.icon ?? "");
        if (iconScore === 0) return false;
        const launchesLocalHelperScript = /(?:^|[ "'`])(?:~|\/home\/[^/]+)?\/?\.local\/share\/applications\/[^ "'`]+\.sh(?:\s|$)/i.test(command);
        const isHelperWrapper = /\bkdialog\b/i.test(command) || launchesLocalHelperScript;
        const isGeneratedToolLauncher = /^[A-Za-z0-9]+_Tools-/.test(appId);
        const isFileOperationWrapper = /(%[fFuUdDnNickvm]|\bffmpeg_[^ "'`]+\.sh\b)/i.test(command);
        const isActionNamedLauncher = /^(add|attach|backup|build|check|clean|compress|concatenate|connect|convert|download|extract|generate|install|mount|normalize|open with|record|rebuild|register|restore|rotate|search|update)\b/i.test(normalizedName);
        const hasActionPrefix = normalizedName.includes(":");
        const isGeneratedActionName = /^(audio|pdf|mp3|immagine|media|ip)\s*:/i.test(normalizedName)
            || /^(mostra|importa|ruota|esegui|imposta|trova|combina|dividi|estrai|massimizza|apri|appiattisci|calcola|cifra)\b/i.test(normalizedName);
        const isShellishLauncher = /(^|[ "'`])(bash|sh|kdialog|xterm|konsole|kitty)(\s|$)/i.test(command)
            || /\b(if|then|else|fi)\b/.test(command)
            || /&&|\|\||;/.test(command);

        if ((hasOnlyToolCategories && isHelperWrapper) || isGeneratedToolLauncher)
            return false;
        if (isActionNamedLauncher && (hasOnlyToolCategories || isHelperWrapper || isFileOperationWrapper))
            return false;
        if (isGeneratedActionName && (isHelperWrapper || isFileOperationWrapper || isShellishLauncher || launchesLocalHelperScript))
            return false;

        return true;
    }

    function dedupeKey(app) {
        const name = normalizeText(app?.name ?? "");
        const startupClass = normalizeText(app?.startupClass ?? "");
        const iconName = normalizeText(app?.icon ?? "");
        const command = normalizedCommand(app);

        if (startupClass.length > 0)
            return `${name}::wmclass:${startupClass}`;
        if (iconPriority(app?.icon ?? "") > 0 && iconName.length > 0)
            return `${name}::icon:${iconName}`;
        return `${name}::cmd:${command}`;
    }

    function preferAppEntry(current, candidate) {
        const currentPriority = iconPriority(current?.icon ?? "");
        const candidatePriority = iconPriority(candidate?.icon ?? "");
        if (candidatePriority !== currentPriority) return candidatePriority > currentPriority ? candidate : current;

        const currentId = String(current?.id ?? "");
        const candidateId = String(candidate?.id ?? "");
        if (candidateId.length !== currentId.length) return candidateId.length < currentId.length ? candidate : current;
        return candidateId.localeCompare(currentId) < 0 ? candidate : current;
    }

    // Filter hidden/non-GUI entries and collapse duplicate desktop files for the same app.
    readonly property list<DesktopEntry> list: {
        const entries = Array.from(DesktopEntries.applications.values).filter(app => shouldShowApp(app));
        const deduped = {};
        const orderedKeys = [];

        for (const app of entries) {
            const key = dedupeKey(app);
            if (!deduped[key]) {
                deduped[key] = app;
                orderedKeys.push(key);
            } else {
                deduped[key] = preferAppEntry(deduped[key], app);
            }
        }

        return orderedKeys.map(key => deduped[key]).filter(Boolean);
    }
    
    readonly property var preppedNames: list.map(a => ({
        name: Fuzzy.prepare(`${a.name} `),
        entry: a
    }))

    readonly property var preppedIcons: list.map(a => ({
        name: Fuzzy.prepare(`${a.icon} `),
        entry: a
    }))

    function fuzzyQuery(search: string): var { // Idk why list<DesktopEntry> doesn't work
        if (root.sloppySearch) {
            const results = list.map(obj => ({
                entry: obj,
                score: Levendist.computeScore(obj.name.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preppedNames, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0) 
            && !iconName.includes("image-missing");
    }

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";

        // Quickshell's desktop entry lookup
        const entry = DesktopEntries.byId(str);
        if (entry) return entry.icon;

        // Normal substitutions
        if (substitutions[str]) return substitutions[str];
        if (substitutions[str.toLowerCase()]) return substitutions[str.toLowerCase()];

        // Regex substitutions
        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str) return replacedName;
        }

        // Icon exists -> return as is
        if (iconExists(str)) return str;


        // Simple guesses
        const lowercased = str.toLowerCase();
        if (iconExists(lowercased)) return lowercased;

        const reverseDomainNameAppName = getReverseDomainNameAppName(str);
        if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;

        const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
        if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;

        const kebabNormalizedGuess = getKebabNormalizedAppName(str);
        if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;

        const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
        if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;

        // Search in desktop entries
        const iconSearchResults = Fuzzy.go(str, preppedIcons, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
        if (iconSearchResults.length > 0) {
            const guess = iconSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        const nameSearchResults = root.fuzzyQuery(str);
        if (nameSearchResults.length > 0) {
            const guess = nameSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        // Quickshell's desktop entry lookup
        const heuristicEntry = DesktopEntries.heuristicLookup(str);
        if (heuristicEntry) return heuristicEntry.icon;

        // Give up
        return "application-x-executable";
    }
}
