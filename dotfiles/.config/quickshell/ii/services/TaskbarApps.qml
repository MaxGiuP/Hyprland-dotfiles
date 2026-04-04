pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    function normalizeAppId(appId) {
        return String(appId ?? "").trim().toLowerCase();
    }

    function resolveDesktopEntry(appId) {
        const normalized = root.normalizeAppId(appId);
        if (normalized.length === 0)
            return null;

        const directEntry = DesktopEntries.byId(String(appId ?? "")) ?? DesktopEntries.byId(normalized);
        if (directEntry)
            return directEntry;

        const baseName = normalized.split(".").slice(-1)[0];
        let bestEntry = null;
        let bestScore = -1;

        for (const entry of DesktopEntries.applications.values) {
            const entryId = root.normalizeAppId(entry?.id);
            const startupClass = root.normalizeAppId(entry?.startupClass);
            if (entryId.length === 0)
                continue;

            let score = -1;
            if (entryId === normalized) score = 100;
            else if (startupClass === normalized) score = 95;
            else if (entryId.endsWith("." + normalized)) score = 90;
            else if (normalized.endsWith("." + entryId)) score = 88;
            else if (baseName.length > 0 && entryId === baseName) score = 85;
            else if (baseName.length > 0 && startupClass === baseName) score = 84;
            else if (baseName.length > 0 && entryId.endsWith("." + baseName)) score = 82;
            else if (baseName.length > 0 && startupClass.endsWith("." + baseName)) score = 80;
            else continue;

            if (score > bestScore) {
                bestEntry = entry;
                bestScore = score;
            }
        }

        return bestEntry ?? DesktopEntries.heuristicLookup(String(appId ?? ""))
            ?? DesktopEntries.heuristicLookup(normalized);
    }

    function resolvedDesktopEntryId(appId) {
        return String(root.resolveDesktopEntry(appId)?.id ?? "").trim();
    }

    function matchingPinnedAppId(appId) {
        const normalized = root.normalizeAppId(appId);
        if (normalized.length === 0 || normalized === "separator")
            return "";

        const pinnedApps = Config.options?.dock.pinnedApps ?? [];
        for (const pinnedId of pinnedApps) {
            if (root.normalizeAppId(pinnedId) === normalized)
                return pinnedId;
        }

        const resolvedEntry = root.resolveDesktopEntry(appId);
        const resolvedEntryId = root.normalizeAppId(resolvedEntry?.id);
        const resolvedStartupClass = root.normalizeAppId(resolvedEntry?.startupClass);
        const resolvedBaseName = resolvedEntryId.split(".").slice(-1)[0];

        for (const pinnedId of pinnedApps) {
            const normalizedPinnedId = root.normalizeAppId(pinnedId);
            const pinnedEntry = root.resolveDesktopEntry(pinnedId);
            const pinnedEntryId = root.normalizeAppId(pinnedEntry?.id);
            const pinnedStartupClass = root.normalizeAppId(pinnedEntry?.startupClass);
            const pinnedBaseName = root.normalizeAppId(pinnedEntry?.id ?? pinnedId).split(".").slice(-1)[0];

            if (resolvedEntryId.length > 0) {
                if (pinnedEntryId === resolvedEntryId
                    || (pinnedStartupClass.length > 0 && pinnedStartupClass === resolvedStartupClass)
                    || normalizedPinnedId === resolvedEntryId
                    || pinnedEntryId === resolvedStartupClass
                    || pinnedStartupClass === resolvedEntryId
                    || pinnedBaseName === resolvedBaseName
                    || pinnedBaseName === resolvedStartupClass)
                    return pinnedId;
            }

            if (normalizedPinnedId.endsWith("." + normalized) || normalized.endsWith("." + normalizedPinnedId))
                return pinnedId;
        }

        return "";
    }

    function canonicalAppId(appId) {
        const normalized = root.normalizeAppId(appId);
        if (normalized.length === 0 || normalized === "separator")
            return normalized;

        const pinnedId = root.matchingPinnedAppId(appId);
        if (pinnedId.length > 0)
            return pinnedId;

        const resolvedEntryId = root.resolvedDesktopEntryId(appId);
        return resolvedEntryId.length > 0 ? resolvedEntryId : normalized;
    }

    function preferredPinnedAppId(appId) {
        const normalized = root.normalizeAppId(appId);
        if (normalized.length === 0 || normalized === "separator")
            return normalized;

        const pinnedId = root.matchingPinnedAppId(appId);
        if (pinnedId.length > 0)
            return pinnedId;

        const resolvedEntryId = root.resolvedDesktopEntryId(appId);
        return resolvedEntryId.length > 0 ? resolvedEntryId : normalized;
    }

    function isPinned(appId) {
        return root.matchingPinnedAppId(appId).length > 0;
    }

    function togglePin(appId) {
        const existingPinnedId = root.matchingPinnedAppId(appId);
        if (existingPinnedId.length > 0) {
            const normalizedPinnedId = root.normalizeAppId(existingPinnedId);
            Config.options.dock.pinnedApps = (Config.options?.dock.pinnedApps ?? []).filter(id => root.normalizeAppId(id) !== normalizedPinnedId)
            return;
        }

        const targetId = root.preferredPinnedAppId(appId);
        if (root.normalizeAppId(targetId).length === 0)
            return;

        Config.options.dock.pinnedApps = (Config.options?.dock.pinnedApps ?? []).concat([targetId])
    }

    function movePinnedApp(appId, targetAppId = "") {
        const pinnedApps = [...(Config.options?.dock.pinnedApps ?? [])];
        const resolvedAppId = root.preferredPinnedAppId(appId);
        const normalizedResolvedAppId = root.normalizeAppId(resolvedAppId);
        const resolvedTargetAppId = targetAppId.length === 0 ? "" : root.preferredPinnedAppId(targetAppId);
        const normalizedResolvedTargetAppId = root.normalizeAppId(resolvedTargetAppId);
        // Filter out appId whether it was pinned or not (pins it at the new position)
        const reorderedApps = pinnedApps.filter(id => root.normalizeAppId(id) !== normalizedResolvedAppId);
        let targetIndex = normalizedResolvedTargetAppId.length === 0
            ? reorderedApps.length
            : reorderedApps.findIndex(id => root.normalizeAppId(id) === normalizedResolvedTargetAppId);
        if (targetIndex < 0) targetIndex = reorderedApps.length;
        reorderedApps.splice(targetIndex, 0, resolvedAppId);
        Config.options.dock.pinnedApps = reorderedApps;
    }

    property list<var> apps: {
        var map = new Map();

        // Pinned apps
        const pinnedApps = Config.options?.dock.pinnedApps ?? [];
        for (const appId of pinnedApps) {
            const key = root.canonicalAppId(appId);
            if (!map.has(key)) map.set(key, ({
                pinned: true,
                toplevels: []
            }));
        }

        // Separator
        if (pinnedApps.length > 0) {
            map.set("SEPARATOR", { pinned: false, toplevels: [] });
        }

        // Ignored apps
        const ignoredRegexStrings = Config.options?.dock.ignoredAppRegexes ?? [];
        const ignoredRegexes = ignoredRegexStrings.map(pattern => new RegExp(pattern, "i"));
        // Open windows
        for (const toplevel of ToplevelManager.toplevels.values) {
            if (ignoredRegexes.some(re => re.test(toplevel.appId))) continue;
            const key = root.canonicalAppId(toplevel.appId);
            if (!map.has(key)) map.set(key, ({
                pinned: false,
                toplevels: []
            }));
            map.get(key).toplevels.push(toplevel);
        }

        var values = [];

        for (const [key, value] of map) {
            values.push(appEntryComp.createObject(null, { appId: key, toplevels: value.toplevels, pinned: value.pinned }));
        }

        return values;
    }

    component TaskbarAppEntry: QtObject {
        id: wrapper
        required property string appId
        required property list<var> toplevels
        required property bool pinned
    }
    Component {
        id: appEntryComp
        TaskbarAppEntry {}
    }
}
