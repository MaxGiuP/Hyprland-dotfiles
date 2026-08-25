pragma Singleton

import Quickshell
import qs.modules.common

Singleton {
    id: root

    readonly property string launcherScriptPath: Quickshell.shellPath("scripts/launch_detached.sh")

    function normalizeCommand(command) {
        if (!Array.isArray(command)) {
            const stringCommand = String(command ?? "").trim();
            return stringCommand.length > 0 ? ["bash", "-lc", stringCommand] : [];
        }

        return command
            .filter(part => part !== undefined && part !== null)
            .map(part => `${part}`);
    }

    function trimFileProtocol(path) {
        const stringPath = String(path ?? "").trim();
        if (!stringPath.startsWith("file://"))
            return stringPath;

        return decodeURIComponent(stringPath.slice(7));
    }

    function desktopFilePath(entry) {
        return trimFileProtocol(entry?.desktopFilePath ?? entry?.path ?? "");
    }

    function desktopLaunchId(entry) {
        return String(entry?.id ?? "").trim().replace(/\.desktop$/i, "");
    }

    function terminalWrapperCommand(command) {
        const normalized = normalizeCommand(command);
        if (normalized.length === 0)
            return [];

        return [
            "bash",
            "-lc",
            `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(normalized.join(" "))}'`
        ];
    }

    function launchCommand(command) {
        const normalized = normalizeCommand(command);
        if (normalized.length === 0)
            return false;

        Quickshell.execDetached([root.launcherScriptPath, ...normalized]);
        return true;
    }

    function launchShellCommand(command) {
        const stringCommand = String(command ?? "").trim();
        if (stringCommand.length === 0)
            return false;

        return launchCommand(["bash", "-lc", stringCommand]);
    }

    function launchDesktopId(appId) {
        const launchId = String(appId ?? "").trim().replace(/\.desktop$/i, "");
        if (launchId.length === 0)
            return false;

        return launchCommand(["gtk-launch", launchId]);
    }

    function launchDesktopFile(entry) {
        const desktopPath = desktopFilePath(entry);
        if (desktopPath.length > 0)
            return launchCommand(["gio", "launch", desktopPath]);

        const launchId = desktopLaunchId(entry);
        if (launchId.length > 0)
            return launchDesktopId(launchId);

        return false;
    }

    function fallbackLaunch(entryOrAction) {
        if (entryOrAction && typeof entryOrAction.execute === "function") {
            entryOrAction.execute();
            return true;
        }

        return false;
    }

    function recordDesktopEntryLaunch(entry) {
        if (!Persistent.ready || !entry)
            return;

        const appId = String(entry.id ?? "").trim();
        if (appId.length === 0)
            return;

        const previousIds = Array.from(Persistent.states.drawer.recentAppIds ?? []);
        Persistent.states.drawer.recentAppIds = [
            appId,
            ...previousIds.filter(id => id !== appId)
        ].slice(0, 32);
    }

    function launchDesktopEntry(entry) {
        if (!entry)
            return false;

        let launched = false;
        if (!entry.runInTerminal && launchDesktopFile(entry))
            launched = true;
        else if (!entry.runInTerminal && launchCommand(entry.command))
            launched = true;
        else if (entry.runInTerminal && launchCommand(terminalWrapperCommand(entry.command)))
            launched = true;
        else
            launched = fallbackLaunch(entry);

        if (launched)
            recordDesktopEntryLaunch(entry);

        return launched;
    }

    function launchDesktopAction(action) {
        if (!action)
            return false;

        if (!action.runInTerminal && launchCommand(action.command))
            return true;

        if (action.runInTerminal && launchCommand(terminalWrapperCommand(action.command)))
            return true;

        return fallbackLaunch(action);
    }
}
