pragma Singleton

import Quickshell
import qs.modules.common

Singleton {
    id: root

    readonly property string launcherScriptPath: Quickshell.shellPath("scripts/launch_detached.sh")

    function normalizeCommand(command) {
        if (!Array.isArray(command))
            return [];

        return command
            .filter(part => part !== undefined && part !== null)
            .map(part => `${part}`);
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
        if (!entry.runInTerminal && launchCommand(entry.command))
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
