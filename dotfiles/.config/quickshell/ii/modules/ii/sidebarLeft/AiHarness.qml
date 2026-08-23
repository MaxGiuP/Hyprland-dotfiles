import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

FocusScope {
    id: root
    focus: true
    activeFocusOnTab: true

    property real padding: 4
    property string homePath: Quickshell.env("HOME") || "/home/linmax"
    property string hermesCommand: `${root.homePath}/.local/bin/hermes`
    property string pythonCommand: `${root.homePath}/.hermes/hermes-agent/venv/bin/python`
    property string hermesVersion: Translation.tr("Checking Hermes...")
    property bool hermesInstalled: false
    property bool busy: false
    property int agentPromptCount: 0
    property int runningMessageIndex: -1
    property var inputField: messageInputField
    property string currentModel: ""
    property string currentProvider: ""
    property string currentModelBaseUrl: ""
    property string currentToolsets: ""
    property string selectedRouteId: Persistent.states.ai.harnessRoute || "codex-cli"
    property bool codexAvailable: false
    property bool geminiAvailable: false
    property bool claudeAvailable: false
    property bool controlsExpanded: false
    property bool showingOllamaManager: false
    property string codexThreadId: ""
    readonly property string codexBaseUrl: "https://chatgpt.com/backend-api/codex"
    readonly property string geminiCloudCodeBaseUrl: "cloudcode-pa://google"
    readonly property string ollamaBaseUrl: "http://localhost:11434/v1"
    readonly property var coreModelRoutes: [
        {
            "id": "codex-cli",
            "label": Translation.tr("Codex CLI"),
            "shortLabel": Translation.tr("Codex"),
            "detail": Translation.tr("Direct route using the signed-in Codex CLI."),
            "icon": "terminal",
            "priority": 0,
            "provider": "codex-cli",
            "model": "codex",
            "baseUrl": "",
            "directAgent": "codex",
            "available": root.codexAvailable
        },
        {
            "id": "gemini-cli-flash",
            "label": Translation.tr("Gemini CLI · Flash"),
            "shortLabel": Translation.tr("Gemini"),
            "detail": Translation.tr("Free Gemini OAuth route for the first backup slot."),
            "icon": "auto_awesome",
            "priority": 1,
            "provider": "google-gemini-cli",
            "model": "gemini-3-flash-preview",
            "baseUrl": root.geminiCloudCodeBaseUrl,
            "available": root.geminiAvailable
        },
        {
            "id": "claude-cli-sonnet",
            "label": Translation.tr("Claude CLI · Sonnet 4.6"),
            "shortLabel": Translation.tr("Claude"),
            "detail": Translation.tr("Claude Code credentials through Hermes' Anthropic route."),
            "icon": "psychology",
            "priority": 2,
            "provider": "anthropic",
            "model": "claude-sonnet-4-6",
            "baseUrl": "",
            "available": root.claudeAvailable
        }
    ]
    readonly property var ollamaModelRoutes: {
        const routes = [];
        if (!Ai.ollamaInstalled)
            return routes;
        if (Ai.localOllamaModels.length === 0) {
            routes.push({
                "id": "ollama-manager",
                "label": Translation.tr("Ollama · Add a model…"),
                "shortLabel": Translation.tr("Ollama"),
                "detail": Translation.tr("Open the local model manager to install an Ollama model."),
                "icon": "memory",
                "priority": 20,
                "provider": "ollama",
                "model": "",
                "baseUrl": root.ollamaBaseUrl,
                "available": true,
                "managerAction": "ollama"
            });
            return routes;
        }
        for (let i = 0; i < Ai.localOllamaModels.length; ++i) {
            const model = String(Ai.localOllamaModels[i] ?? "").trim();
            if (model.length === 0)
                continue;
            routes.push({
                "id": `ollama-${root.safeRouteId(model)}`,
                "label": Translation.tr("Ollama · %1").arg(Ai.guessModelName(model)),
                "shortLabel": Ai.guessModelName(model),
                "detail": Ai.ollamaRunning
                    ? Translation.tr("Local Ollama fallback model.")
                    : Translation.tr("Local Ollama fallback model. Runtime is offline."),
                "icon": "memory",
                "priority": 20 + i,
                "provider": "custom",
                "model": model,
                "baseUrl": root.ollamaBaseUrl,
                "available": true,
                "local": true
            });
        }
        return routes;
    }
    readonly property var availableModelRoutes: {
        const routes = [];
        for (let i = 0; i < root.coreModelRoutes.length; ++i) {
            const route = root.coreModelRoutes[i];
            if (route.available)
                routes.push(route);
        }
        for (let i = 0; i < root.ollamaModelRoutes.length; ++i)
            routes.push(root.ollamaModelRoutes[i]);
        if (routes.length === 0 && root.currentModel.length > 0 && root.currentProvider.length > 0) {
            routes.push({
                "id": root.routeIdForConfig(root.currentProvider, root.currentModel, root.currentModelBaseUrl),
                "label": root.configuredRouteLabel(root.currentProvider, root.currentModel),
                "shortLabel": root.currentModel,
                "detail": Translation.tr("Currently configured Hermes route."),
                "icon": "tune",
                "priority": 99,
                "provider": root.currentProvider,
                "model": root.currentModel,
                "baseUrl": root.currentModelBaseUrl,
                "available": true,
                "configuredOnly": true
            });
        }
        return routes.sort((a, b) => (a.priority ?? 99) - (b.priority ?? 99));
    }
    readonly property int selectedRouteIndex: root.indexForRouteId(root.selectedRouteId)
    readonly property int effectiveRouteIndex: root.selectedRouteIndex >= 0 ? root.selectedRouteIndex : (root.availableModelRoutes.length > 0 ? 0 : -1)
    readonly property var selectedRoute: root.effectiveRouteIndex >= 0 ? root.availableModelRoutes[root.effectiveRouteIndex] : null
    readonly property string displayedModel: root.trimmed(root.selectedRoute?.model ?? root.currentModel)
    readonly property string displayedProvider: root.trimmed(root.selectedRoute?.provider ?? root.currentProvider)
    readonly property var selectedFallbackRoutes: root.selectedRoute ? root.fallbackRoutesFor(root.selectedRoute) : []
    readonly property var selectedRouteChain: root.selectedRoute ? [root.selectedRoute].concat(root.selectedFallbackRoutes) : []
    readonly property var installedOllamaLabels: {
        const labels = [];
        for (let i = 0; i < Math.min(Ai.localOllamaModels.length, 4); ++i)
            labels.push(Ai.guessModelName(Ai.localOllamaModels[i]));
        if (Ai.localOllamaModels.length > labels.length)
            labels.push(Translation.tr("+%1 more").arg(Ai.localOllamaModels.length - labels.length));
        return labels;
    }

    function shellQuote(value) {
        return `'${StringUtils.shellSingleQuoteEscape(value ?? "")}'`;
    }

    function trimmed(value) {
        return String(value ?? "").trim();
    }

    function normalizedBaseUrl(value) {
        return root.trimmed(value).replace(/\/+$/, "");
    }

    function safeRouteId(value) {
        return root.trimmed(value).replace(/[^A-Za-z0-9_.-]/g, "_");
    }

    function configuredRouteLabel(provider, model) {
        const providerText = root.trimmed(provider);
        const modelText = root.trimmed(model);
        if (providerText.length === 0)
            return modelText;
        if (modelText.length === 0)
            return providerText;
        return `${providerText} · ${modelText}`;
    }

    function routeIdForConfig(provider, model, baseUrl) {
        const cleanProvider = root.trimmed(provider).toLowerCase();
        const cleanModel = root.trimmed(model);
        const cleanBaseUrl = root.normalizedBaseUrl(baseUrl).toLowerCase();
        if (cleanProvider === "codex-cli")
            return "codex-cli";
        if (cleanProvider === "google-gemini-cli" && cleanModel === "gemini-3-flash-preview")
            return "gemini-cli-flash";
        if (cleanProvider === "anthropic" && cleanModel === "claude-sonnet-4-6")
            return "claude-cli-sonnet";
        if (cleanProvider === "custom" && cleanBaseUrl.indexOf("localhost:11434") !== -1)
            return `ollama-${root.safeRouteId(cleanModel)}`;
        if (cleanProvider.length > 0 && cleanModel.length > 0)
            return `configured-${root.safeRouteId(cleanProvider)}-${root.safeRouteId(cleanModel)}-${root.safeRouteId(cleanBaseUrl)}`;
        return "";
    }

    function indexForRouteId(routeId) {
        const cleanId = root.trimmed(routeId);
        if (cleanId.length === 0)
            return -1;
        for (let i = 0; i < root.availableModelRoutes.length; ++i) {
            if (root.availableModelRoutes[i].id === cleanId)
                return i;
        }
        return -1;
    }

    function routeIdentity(route) {
        if (!route)
            return "";
        return [
            root.trimmed(route.provider).toLowerCase(),
            root.trimmed(route.model).toLowerCase(),
            root.normalizedBaseUrl(route.baseUrl).toLowerCase()
        ].join("|");
    }

    function routeConfigEntry(route) {
        const entry = {
            "provider": root.trimmed(route?.provider),
            "model": root.trimmed(route?.model)
        };
        const baseUrl = root.normalizedBaseUrl(route?.baseUrl);
        const apiMode = root.trimmed(route?.apiMode);
        if (baseUrl.length > 0)
            entry["base_url"] = baseUrl;
        if (apiMode.length > 0)
            entry["api_mode"] = apiMode;
        return entry;
    }

    function fallbackRoutesFor(primaryRoute) {
        if (!primaryRoute)
            return [];
        if ((primaryRoute.directAgent ?? "").length > 0)
            return [];

        const primaryId = primaryRoute.id ?? "";
        const primaryIdentity = root.routeIdentity(primaryRoute);
        const seen = {};
        seen[primaryIdentity] = true;
        const routes = [];
        for (let i = 0; i < root.availableModelRoutes.length; ++i) {
            const route = root.availableModelRoutes[i];
            if (!route || route.id === primaryId || route.configuredOnly || (route.managerAction ?? "").length > 0)
                continue;
            const identity = root.routeIdentity(route);
            if (seen[identity])
                continue;
            seen[identity] = true;
            routes.push(route);
        }
        return routes;
    }

    function selectModelRoute(route, persist) {
        if (!route)
            return;
        root.selectedRouteId = route.id ?? "";
        Persistent.states.ai.harnessRoute = root.selectedRouteId;
        root.currentModel = root.trimmed(route.model);
        root.currentProvider = root.trimmed(route.provider);
        root.currentModelBaseUrl = root.normalizedBaseUrl(route.baseUrl);
        if (persist)
            root.saveModelRoute(route);
    }

    function saveModelRoute(route) {
        if (!route || root.busy)
            return;
        if ((route.directAgent ?? "").length > 0)
            return;

        const toolsets = root.currentToolsets.trim().split(",").map(item => item.trim()).filter(item => item.length > 0);
        const payload = root.routeConfigEntry(route);
        payload["fallback_providers"] = [];
        payload["toolsets"] = toolsets;
        const fallbackRoutes = root.fallbackRoutesFor(route);
        for (let i = 0; i < fallbackRoutes.length; ++i)
            payload["fallback_providers"].push(root.routeConfigEntry(fallbackRoutes[i]));

        const payloadLiteral = JSON.stringify(JSON.stringify(payload));
        const script = [
            "import json, pathlib, yaml",
            `payload = json.loads(${payloadLiteral})`,
            "path = pathlib.Path.home() / '.hermes' / 'config.yaml'",
            "cfg = yaml.safe_load(path.read_text()) if path.exists() else {}",
            "cfg = cfg if isinstance(cfg, dict) else {}",
            "model = cfg.get('model') if isinstance(cfg.get('model'), dict) else {}",
            "model['default'] = payload['model']",
            "model['provider'] = payload['provider']",
            "base_url = payload.get('base_url') or ''",
            "if base_url:",
            "    model['base_url'] = base_url",
            "else:",
            "    model.pop('base_url', None)",
            "api_mode = payload.get('api_mode') or ''",
            "if api_mode:",
            "    model['api_mode'] = api_mode",
            "else:",
            "    model.pop('api_mode', None)",
            "cfg['model'] = model",
            "toolsets = payload.get('toolsets') or []",
            "if toolsets:",
            "    cfg['toolsets'] = toolsets",
            "cfg['fallback_providers'] = payload.get('fallback_providers') or []",
            "cfg.pop('fallback_model', None)",
            "path.parent.mkdir(parents=True, exist_ok=True)",
            "path.write_text(yaml.safe_dump(cfg, sort_keys=False, default_flow_style=False))",
            "print('Primary: ' + payload['model'] + ' via ' + payload['provider'])",
            "fallbacks = payload.get('fallback_providers') or []",
            "print('Fallbacks: ' + (' -> '.join((entry.get('model', '?') + ' via ' + entry.get('provider', '?')) for entry in fallbacks) if fallbacks else 'none'))"
        ].join("\n");
        root.runHermesShell(Translation.tr("Hermes model route"), `${root.shellQuote(root.pythonCommand)} -c ${root.shellQuote(script)}`);
    }

    function formatOllamaStatus() {
        if (!Ai.ollamaInstalled)
            return Translation.tr("Ollama is not detected.");
        if (Ai.localOllamaModels.length === 0)
            return Ai.ollamaRunning
                ? Translation.tr("Ollama is online with no installed local models.")
                : Translation.tr("Ollama is offline with no installed local models detected.");
        return Ai.ollamaRunning
            ? Translation.tr("%1 local models ready.").arg(Ai.localOllamaModels.length)
            : Translation.tr("%1 local models installed, runtime offline.").arg(Ai.localOllamaModels.length);
    }

    function buildGuard() {
        const hermes = root.shellQuote(root.hermesCommand);
        const home = root.shellQuote(root.homePath);
        return `[ -x ${hermes} ] || { echo "Hermes launcher not found at ${root.hermesCommand}"; exit 127; }; cd ${home} || exit 1; `;
    }

    function stripAnsi(value) {
        return String(value ?? "")
            .replace(/\x1B\[[0-9;?]*[ -/]*[@-~]/g, "")
            .replace(/\r/g, "")
            .trim();
    }

    function requestScrollToEnd() {
        scrollToEndTimer.restart();
    }

    function addMessage(messageRole, title, content, streaming = false) {
        messageListModel.append({
            "messageRole": messageRole,
            "title": title,
            "content": content,
            "timeText": Qt.formatTime(new Date(), "HH:mm"),
            "streaming": streaming
        });
        root.requestScrollToEnd();
        return messageListModel.count - 1;
    }

    function updateMessage(index, content, final = false) {
        if (index < 0 || index >= messageListModel.count)
            return;
        messageListModel.setProperty(index, "content", content);
        if (final)
            messageListModel.setProperty(index, "streaming", false);
        root.requestScrollToEnd();
    }

    function focusActiveItem() {
        if (root.showingOllamaManager)
            ollamaManagerLoader.item?.focusActiveItem();
        else
            root.inputField.forceActiveFocus();
    }

    function buildOneShotCommand(prompt) {
        const parts = [root.shellQuote(root.hermesCommand)];
        const model = root.currentModel.trim();
        const provider = root.currentProvider.trim();
        const toolsets = root.currentToolsets.trim();

        if (continueSwitch.switchChecked && root.agentPromptCount > 0)
            parts.push("--continue");
        if (model.length > 0)
            parts.push("--model", root.shellQuote(model));
        if (provider.length > 0)
            parts.push("--provider", root.shellQuote(provider));
        if (toolsets.length > 0)
            parts.push("--toolsets", root.shellQuote(toolsets));
        if (worktreeSwitch.switchChecked)
            parts.push("--worktree");
        if (yoloSwitch.switchChecked)
            parts.push("--yolo");

        parts.push("--oneshot", root.shellQuote(prompt));
        return root.buildGuard() + parts.join(" ");
    }

    function buildCodexCommand(prompt) {
        if (continueSwitch.switchChecked && root.codexThreadId.length > 0) {
            return [
                "codex", "exec", "resume",
                "--json", "--skip-git-repo-check",
                root.codexThreadId, prompt
            ];
        }
        return [
            "codex", "exec",
            "--json", "--skip-git-repo-check",
            "--color", "never", "--sandbox", "read-only",
            "-C", root.homePath, prompt
        ];
    }

    function processCodexEvent(line) {
        const cleanLine = String(line ?? "").trim();
        if (cleanLine.length === 0)
            return;

        try {
            const event = JSON.parse(cleanLine);
            if (event.type === "thread.started" && event.thread_id) {
                root.codexThreadId = String(event.thread_id);
                return;
            }
            if (event.type === "item.completed" && event.item?.type === "agent_message") {
                const answer = String(event.item.text ?? "").trim();
                if (answer.length > 0) {
                    agentProc.codexAnswer = answer;
                    root.updateMessage(root.runningMessageIndex, answer);
                }
                return;
            }
            if (event.type === "turn.failed" || event.type === "error") {
                const message = String(event.error?.message ?? event.message ?? cleanLine);
                agentProc.errBuffer += message + "\n";
            }
        } catch (e) {
            agentProc.errBuffer += cleanLine + "\n";
        }
    }

    function sendPrompt(prompt) {
        const cleanPrompt = String(prompt ?? "").trim();
        if (cleanPrompt.length === 0 || root.busy)
            return;

        root.addMessage("user", Translation.tr("You"), cleanPrompt);
        const responseTitle = (root.selectedRoute?.directAgent ?? "") === "codex" ? Translation.tr("Codex") : Translation.tr("Hermes");
        root.runningMessageIndex = root.addMessage("assistant", responseTitle, Translation.tr("Working..."), true);
        agentProc.buffer = "";
        agentProc.errBuffer = "";
        agentProc.codexAnswer = "";
        agentProc.codexJson = (root.selectedRoute?.directAgent ?? "") === "codex";
        agentProc.command = agentProc.codexJson
            ? root.buildCodexCommand(cleanPrompt)
            : ["bash", "-c", root.buildOneShotCommand(cleanPrompt)];
        root.agentPromptCount += 1;
        root.busy = true;
        agentProc.running = true;
    }

    function updateRunningOutput() {
        const output = root.stripAnsi(agentProc.buffer);
        const errors = root.stripAnsi(agentProc.errBuffer);
        const shown = output.length > 0 ? output : errors;
        if (shown.length > 0)
            root.updateMessage(root.runningMessageIndex, shown);
    }

    function updateCommandOutput() {
        const shown = root.stripAnsi(commandProc.buffer + "\n" + commandProc.errBuffer);
        if (shown.length > 0)
            root.updateMessage(root.runningMessageIndex, shown);
    }

    function runHermesCommand(title, args) {
        if (root.busy)
            return;
        root.runningMessageIndex = root.addMessage("system", title, Translation.tr("Running..."), true);
        commandProc.buffer = "";
        commandProc.errBuffer = "";
        commandProc.command = ["bash", "-c", `${root.buildGuard()}${root.shellQuote(root.hermesCommand)} ${args}`];
        root.busy = true;
        commandProc.running = true;
    }

    function runHermesShell(title, script) {
        if (root.busy)
            return;
        root.runningMessageIndex = root.addMessage("system", title, Translation.tr("Running..."), true);
        commandProc.buffer = "";
        commandProc.errBuffer = "";
        commandProc.command = ["bash", "-c", root.buildGuard() + script];
        root.busy = true;
        commandProc.running = true;
    }

    function openHermesCommand(args) {
        const command = `${root.buildGuard()}${root.shellQuote(root.hermesCommand)} ${args}; code=$?; echo; echo "Hermes command exited with $code."; exec fish -i`;
        Quickshell.execDetached([
            "bash",
            "-lc",
            `${Config.options.apps.terminal} -e bash -lc ${root.shellQuote(command)}`
        ]);
    }

    function saveConfigValue(key, value) {
        const cleanValue = String(value ?? "").trim();
        if (cleanValue.length === 0 || root.busy)
            return;
        root.runHermesCommand(Translation.tr("Hermes config"), `config set ${root.shellQuote(key)} ${root.shellQuote(cleanValue)}`);
    }

    function saveBasicSettings() {
        if (root.selectedRoute)
            root.saveModelRoute(root.selectedRoute);
    }

    function refreshHermesSummary() {
        hermesVersionProc.running = false;
        configSummaryProc.running = false;
        routeCodexCheckProc.running = false;
        routeGeminiCheckProc.running = false;
        routeClaudeCheckProc.running = false;
        hermesVersionProc.running = true;
        configSummaryProc.running = true;
        routeCodexCheckProc.running = true;
        routeGeminiCheckProc.running = true;
        routeClaudeCheckProc.running = true;
        Ai.refreshOllamaStatus();
    }

    onActiveFocusChanged: {
        if (activeFocus)
            Qt.callLater(root.focusActiveItem);
    }

    onVisibleChanged: {
        if (visible)
            Qt.callLater(root.focusActiveItem);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && root.showingOllamaManager) {
            root.showingOllamaManager = false;
            Qt.callLater(root.focusActiveItem);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Escape && root.busy) {
            agentProc.running = false;
            commandProc.running = false;
            agentOutputFlushTimer.stop();
            commandOutputFlushTimer.stop();
            root.busy = false;
            root.updateMessage(root.runningMessageIndex, Translation.tr("Stopped."), true);
            event.accepted = true;
        }
    }

    ListModel {
        id: messageListModel
    }

    Timer {
        id: scrollToEndTimer
        interval: 16
        repeat: false
        onTriggered: messageListView.positionViewAtEnd()
    }

    Timer {
        id: agentOutputFlushTimer
        interval: 80
        repeat: false
        onTriggered: root.updateRunningOutput()
    }

    Timer {
        id: commandOutputFlushTimer
        interval: 80
        repeat: false
        onTriggered: root.updateCommandOutput()
    }

    Process {
        id: hermesVersionProc
        running: true
        command: [root.hermesCommand, "--version"]
        stdout: StdioCollector {
            id: hermesVersionCollector
            onStreamFinished: {
                const text = hermesVersionCollector.text.trim();
                root.hermesInstalled = text.length > 0;
                root.hermesVersion = text.length > 0 ? text : Translation.tr("Hermes not found");
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.hermesInstalled = false;
                root.hermesVersion = Translation.tr("Hermes not found");
            }
        }
    }

    Process {
        id: configSummaryProc
        running: true
        command: [
            root.pythonCommand,
            "-c",
            "import json, pathlib, yaml\np = pathlib.Path.home() / '.hermes' / 'config.yaml'\ncfg = yaml.safe_load(p.read_text()) if p.exists() else {}\ncfg = cfg or {}\nmodel = cfg.get('model') if isinstance(cfg.get('model'), dict) else {}\nagent = cfg.get('agent') if isinstance(cfg.get('agent'), dict) else {}\ntoolsets = cfg.get('toolsets') if isinstance(cfg.get('toolsets'), list) else []\nprint(json.dumps({'model': str(model.get('default') or ''), 'provider': str(model.get('provider') or ''), 'base_url': str(model.get('base_url') or ''), 'toolsets': ','.join(str(x) for x in toolsets), 'max_turns': str(agent.get('max_turns') or '')}))"
        ]
        stdout: StdioCollector {
            id: configSummaryCollector
            onStreamFinished: {
                try {
                    const data = JSON.parse(configSummaryCollector.text.trim() || "{}");
                    root.currentModel = data.model ?? "";
                    root.currentProvider = data.provider ?? "";
                    root.currentModelBaseUrl = data.base_url ?? "";
                    root.currentToolsets = data.toolsets ?? "";
                    if (root.selectedRouteId.length === 0)
                        root.selectedRouteId = root.routeIdForConfig(root.currentProvider, root.currentModel, root.currentModelBaseUrl);
                } catch (e) {
                    console.log("[AiHarness] Could not parse Hermes config summary:", e);
                }
            }
        }
    }

    Process {
        id: routeCodexCheckProc
        running: true
        command: ["bash", "-lc", "command -v codex >/dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.codexAvailable = exitCode === 0;
        }
    }

    Process {
        id: routeGeminiCheckProc
        running: true
        command: [
            "bash",
            "-lc",
            `command -v gemini >/dev/null 2>&1 && test -s ${root.shellQuote(`${root.homePath}/.hermes/auth/google_oauth.json`)}`
        ]
        onExited: (exitCode, exitStatus) => {
            root.geminiAvailable = exitCode === 0;
        }
    }

    Process {
        id: routeClaudeCheckProc
        running: true
        command: [
            "bash",
            "-lc",
            `command -v claude >/dev/null 2>&1 && test -s ${root.shellQuote(`${root.homePath}/.claude/.credentials.json`)}`
        ]
        onExited: (exitCode, exitStatus) => {
            root.claudeAvailable = exitCode === 0;
        }
    }

    Process {
        id: ollamaServeProc
        command: ["ollama", "serve"]

        onRunningChanged: {
            if (!running)
                Qt.callLater(() => Ai.refreshOllamaStatus());
        }
    }

    Process {
        id: ollamaKillProc
        command: ["pkill", "ollama"]

        onExited: Qt.callLater(() => Ai.refreshOllamaStatus())
    }

    Process {
        id: agentProc
        property string buffer: ""
        property string errBuffer: ""
        property string codexAnswer: ""
        property bool codexJson: false
        stdout: SplitParser {
            onRead: data => {
                if (agentProc.codexJson) {
                    root.processCodexEvent(data);
                    return;
                }
                agentProc.buffer += data + "\n";
                agentOutputFlushTimer.restart();
            }
        }
        stderr: SplitParser {
            onRead: data => {
                agentProc.errBuffer += data + "\n";
                if (!agentProc.codexJson)
                    agentOutputFlushTimer.restart();
            }
        }
        onExited: (exitCode, exitStatus) => {
            agentOutputFlushTimer.stop();
            const output = root.stripAnsi(agentProc.buffer);
            const errors = root.stripAnsi(agentProc.errBuffer);
            let finalText = agentProc.codexAnswer.length > 0
                ? agentProc.codexAnswer
                : (output.length > 0 ? output : errors);
            if (finalText.length === 0)
                finalText = exitCode === 0 ? Translation.tr("No output.") : Translation.tr("Model exited without output.");
            if (exitCode !== 0)
                finalText = Translation.tr("Model failed with exit %1.").arg(exitCode) + "\n\n" + finalText;
            root.updateMessage(root.runningMessageIndex, finalText, true);
            agentProc.buffer = "";
            agentProc.errBuffer = "";
            agentProc.codexAnswer = "";
            agentProc.codexJson = false;
            root.busy = false;
            Qt.callLater(root.focusActiveItem);
        }
    }

    Process {
        id: commandProc
        property string buffer: ""
        property string errBuffer: ""
        stdout: SplitParser {
            onRead: data => {
                commandProc.buffer += data + "\n";
                commandOutputFlushTimer.restart();
            }
        }
        stderr: SplitParser {
            onRead: data => {
                commandProc.errBuffer += data + "\n";
                commandOutputFlushTimer.restart();
            }
        }
        onExited: (exitCode, exitStatus) => {
            commandOutputFlushTimer.stop();
            const output = root.stripAnsi(commandProc.buffer);
            const errors = root.stripAnsi(commandProc.errBuffer);
            let finalText = output.length > 0 ? output : errors;
            if (finalText.length === 0)
                finalText = exitCode === 0 ? Translation.tr("Done.") : Translation.tr("Command exited without output.");
            if (exitCode !== 0)
                finalText = Translation.tr("Hermes command failed with exit %1.").arg(exitCode) + "\n\n" + finalText;
            root.updateMessage(root.runningMessageIndex, finalText, true);
            commandProc.buffer = "";
            commandProc.errBuffer = "";
            root.busy = false;
            root.refreshHermesSummary();
            Qt.callLater(root.focusActiveItem);
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding
        visible: !root.showingOllamaManager

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            RowLayout {
                id: headerRow
                anchors {
                    fill: parent
                    margins: 10
                }
                spacing: 8

                MaterialSymbol {
                    text: "hub"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer2
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("AI Harness")
                        color: Appearance.colors.colOnLayer2
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.title
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.selectedRoute?.label ?? (root.currentModel.length > 0 ? root.currentModel : Translation.tr("No model selected"))
                        color: root.hermesInstalled ? Appearance.colors.colSubtext : Appearance.colors.colError
                        font.pixelSize: Appearance.font.pixelSize.small
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: Ai.ollamaRunning ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                    colBackgroundHover: Ai.ollamaRunning ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3Hover
                    onClicked: {
                        root.showingOllamaManager = true;
                        Ai.refreshOllamaStatus();
                        Qt.callLater(root.focusActiveItem);
                    }

                    contentItem: MaterialSymbol {
                        text: "memory"
                        iconSize: 18
                        color: Ai.ollamaRunning ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    StyledToolTip {
                        text: Translation.tr("Open Ollama models")
                    }
                }

                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    toggled: root.controlsExpanded
                    onClicked: root.controlsExpanded = !root.controlsExpanded

                    contentItem: MaterialSymbol {
                        text: root.controlsExpanded ? "expand_less" : "tune"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer3
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    StyledToolTip {
                        text: root.controlsExpanded ? Translation.tr("Hide controls") : Translation.tr("Show controls")
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            visible: root.controlsExpanded
            spacing: 6

            HarnessActionButton {
                buttonIcon: "refresh"
                label: Translation.tr("Refresh")
                tooltip: Translation.tr("Refresh Hermes status")
                triggerAction: () => root.refreshHermesSummary()
            }

            HarnessActionButton {
                buttonIcon: root.busy ? "stop" : "terminal"
                label: root.busy ? Translation.tr("Stop") : Translation.tr("TUI")
                tooltip: root.busy ? Translation.tr("Stop running Hermes command") : Translation.tr("Open Hermes TUI in a terminal")
                triggerAction: () => {
                    if (root.busy) {
                        agentProc.running = false;
                        commandProc.running = false;
                        root.busy = false;
                        root.updateMessage(root.runningMessageIndex, Translation.tr("Stopped."));
                    } else {
                        root.openHermesCommand("--tui");
                    }
                }
            }

            HarnessActionButton {
                buttonIcon: "monitor_heart"
                label: Translation.tr("Status")
                tooltip: Translation.tr("Run Hermes status")
                triggerAction: () => root.runHermesCommand(Translation.tr("Hermes status"), "status")
            }

            HarnessActionButton {
                buttonIcon: "settings"
                label: Translation.tr("Setup")
                tooltip: Translation.tr("Open Hermes setup")
                triggerAction: () => root.openHermesCommand("setup")
            }

            HarnessActionButton {
                buttonIcon: "model_training"
                label: Translation.tr("Model")
                tooltip: Translation.tr("Open Hermes model picker")
                triggerAction: () => root.openHermesCommand("model")
            }

            HarnessActionButton {
                buttonIcon: "construction"
                label: Translation.tr("Tools")
                tooltip: Translation.tr("Open Hermes tool settings")
                triggerAction: () => root.openHermesCommand("tools")
            }

            HarnessActionButton {
                buttonIcon: "health_and_safety"
                label: Translation.tr("Doctor")
                tooltip: Translation.tr("Run Hermes diagnostics")
                triggerAction: () => root.runHermesCommand(Translation.tr("Hermes doctor"), "doctor")
            }

            HarnessActionButton {
                buttonIcon: "history"
                label: Translation.tr("Sessions")
                tooltip: Translation.tr("Browse Hermes sessions")
                triggerAction: () => root.openHermesCommand("sessions browse")
            }

            HarnessActionButton {
                buttonIcon: "edit"
                label: Translation.tr("Config")
                tooltip: Translation.tr("Open Hermes config")
                triggerAction: () => root.openHermesCommand("config edit")
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: settingsColumn.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            clip: true

            ColumnLayout {
                id: settingsColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 8
                }
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledComboBox {
                        id: modelRouteCombo
                        Layout.fillWidth: true
                        implicitHeight: 38
                        enabled: !root.busy && root.availableModelRoutes.length > 0
                        editable: false
                        model: root.availableModelRoutes
                        textRole: "label"
                        currentIndex: root.effectiveRouteIndex
                        onActivated: index => {
                            const route = root.availableModelRoutes[index];
                            if ((route?.managerAction ?? "") === "ollama") {
                                root.showingOllamaManager = true;
                                Ai.refreshOllamaStatus();
                                Qt.callLater(root.focusActiveItem);
                                return;
                            }
                            root.selectModelRoute(route, true);
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.controlsExpanded && root.selectedRoute !== null
                    text: root.selectedRoute?.detail ?? ""
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.availableModelRoutes.length === 0
                    text: Translation.tr("No paired AI routes detected.")
                    color: Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.WordWrap
                }

                Flow {
                    Layout.fillWidth: true
                    visible: root.controlsExpanded && root.selectedRouteChain.length > 0
                    spacing: 6

                    Repeater {
                        model: root.selectedRouteChain

                        delegate: RouteChip {
                            required property var modelData
                            required property int index
                            chipIcon: modelData.icon ?? "smart_toy"
                            chipText: index === 0
                                ? Translation.tr("Primary: %1").arg(modelData.shortLabel ?? modelData.label)
                                : Translation.tr("Fallback: %1").arg(modelData.shortLabel ?? modelData.label)
                            primary: index === 0
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.controlsExpanded
                    spacing: 6

                    MaterialSymbol {
                        text: "memory"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                        Layout.alignment: Qt.AlignTop
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Ollama fallback")
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.formatOllamaStatus()
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            wrapMode: Text.WordWrap
                        }
                    }

                    ButtonGroup {
                        ApiCommandButton {
                            buttonText: Translation.tr("Refresh")
                            downAction: () => Ai.refreshOllamaStatus()
                        }

                        ApiCommandButton {
                            enabled: Ai.ollamaInstalled
                            buttonText: Ai.ollamaRunning ? Translation.tr("Stop") : Translation.tr("Start")
                            downAction: () => {
                                if (!Ai.ollamaInstalled)
                                    return;
                                if (Ai.ollamaRunning) {
                                    ollamaServeProc.running = false;
                                    ollamaKillProc.running = true;
                                } else {
                                    ollamaServeProc.running = true;
                                }
                            }
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    visible: root.controlsExpanded && root.installedOllamaLabels.length > 0
                    spacing: 6

                    Repeater {
                        model: root.installedOllamaLabels

                        delegate: RouteChip {
                            required property string modelData
                            chipIcon: "memory"
                            chipText: modelData
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.controlsExpanded
                    spacing: 6

                    InlineSwitch {
                        id: continueSwitch
                        label: Translation.tr("Continue")
                        buttonIcon: "history"
                        switchChecked: true
                    }

                    InlineSwitch {
                        id: worktreeSwitch
                        label: Translation.tr("Worktree")
                        buttonIcon: "account_tree"
                    }

                    InlineSwitch {
                        id: yoloSwitch
                        label: Translation.tr("YOLO")
                        buttonIcon: "bolt"
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            clip: true

            ListView {
                id: messageListView
                anchors.fill: parent
                anchors.margins: 6
                model: messageListModel
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                reuseItems: true
                cacheBuffer: 400

                delegate: Item {
                    id: messageDelegate
                    required property string messageRole
                    required property string title
                    required property string content
                    required property string timeText
                    required property bool streaming

                    width: messageListView.width
                    height: bubble.height
                    implicitHeight: bubble.implicitHeight

                    Rectangle {
                        id: bubble
                        width: messageDelegate.messageRole === "user"
                            ? Math.min(messageDelegate.width * 0.86, 520)
                            : messageDelegate.width
                        height: implicitHeight
                        implicitHeight: bubbleColumn.implicitHeight + 16
                        anchors.right: messageDelegate.messageRole === "user" ? parent.right : undefined
                        anchors.left: messageDelegate.messageRole === "user" ? undefined : parent.left
                        radius: Appearance.rounding.normal
                        color: {
                            if (messageDelegate.messageRole === "user")
                                return Appearance.colors.colPrimaryContainer;
                            if (messageDelegate.messageRole === "system")
                                return Appearance.colors.colSecondaryContainer;
                            return Appearance.colors.colLayer2;
                        }
                        border.width: messageDelegate.messageRole === "assistant" ? 1 : 0
                        border.color: Appearance.colors.colLayer2Hover

                        ColumnLayout {
                            id: bubbleColumn
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: 8
                            }
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    text: messageDelegate.title
                                    color: messageDelegate.messageRole === "user"
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colOnLayer2
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    text: messageDelegate.timeText
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }

                            TextArea {
                                Layout.fillWidth: true
                                readOnly: true
                                selectByMouse: true
                                background: null
                                padding: 0
                                wrapMode: TextEdit.Wrap
                                textFormat: messageDelegate.messageRole === "assistant" && !messageDelegate.streaming
                                    ? TextEdit.MarkdownText
                                    : TextEdit.PlainText
                                text: messageDelegate.content
                                color: messageDelegate.messageRole === "user"
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnLayer2
                                selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                                selectionColor: Appearance.colors.colSecondaryContainer
                                font.family: messageDelegate.messageRole === "system"
                                    ? Appearance.font.family.monospace
                                    : Appearance.font.family.reading
                                font.pixelSize: Appearance.font.pixelSize.small
                                implicitHeight: contentHeight

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.NoButton
                                    hoverEnabled: true
                                    cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                                }

                                onLinkActivated: link => Qt.openUrlExternally(link)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: messageListModel.count === 0
                    color: "transparent"

                    Column {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "hub"
                            iconSize: 24
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            text: Translation.tr("Hermes")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }
        }

        Rectangle {
            id: inputWrapper
            property real spacing: 5
            readonly property real expandedImplicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + spacing, 45)
            z: 10
            Layout.fillWidth: true
            radius: Appearance.rounding.normal - root.padding
            color: Appearance.colors.colLayer2
            implicitHeight: expandedImplicitHeight
            clip: true
            layer.enabled: true

            RowLayout {
                id: inputFieldRowLayout
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 5
                }
                spacing: 0

                StyledTextArea {
                    id: messageInputField
                    wrapMode: TextArea.Wrap
                    Layout.fillWidth: true
                    padding: 10
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    placeholderText: Translation.tr("Message Hermes...")
                    background: null

                    function accept() {
                        const inputText = text;
                        text = "";
                        root.sendPrompt(inputText);
                    }

                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                messageInputField.insert(messageInputField.cursorPosition, "\n");
                            } else {
                                messageInputField.accept();
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape && root.busy) {
                            agentProc.running = false;
                            commandProc.running = false;
                            agentOutputFlushTimer.stop();
                            commandOutputFlushTimer.stop();
                            root.busy = false;
                            root.updateMessage(root.runningMessageIndex, Translation.tr("Stopped."), true);
                            event.accepted = true;
                        }
                    }
                }

                RippleButton {
                    id: sendButton
                    Layout.alignment: Qt.AlignTop
                    Layout.rightMargin: 5
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    enabled: messageInputField.text.trim().length > 0 || root.busy
                    toggled: enabled

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (root.busy) {
                                agentProc.running = false;
                                commandProc.running = false;
                                agentOutputFlushTimer.stop();
                                commandOutputFlushTimer.stop();
                                root.busy = false;
                                root.updateMessage(root.runningMessageIndex, Translation.tr("Stopped."), true);
                                return;
                            }
                            const inputText = messageInputField.text;
                            messageInputField.clear();
                            root.sendPrompt(inputText);
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                        text: root.busy ? "stop" : "arrow_upward"
                    }
                }
            }

            RowLayout {
                id: commandButtonsRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                anchors.leftMargin: 10
                anchors.rightMargin: 5
                spacing: 4

                ApiInputBoxIndicator {
                    icon: "api"
                    text: root.displayedModel.length > 0 ? root.displayedModel : Translation.tr("default")
                    tooltipText: Translation.tr("Selected model")
                }

                ApiInputBoxIndicator {
                    visible: root.displayedProvider.length > 0
                    icon: "hub"
                    text: root.displayedProvider
                    tooltipText: Translation.tr("Selected provider")
                }

                Item {
                    Layout.fillWidth: true
                }

                ButtonGroup {
                    padding: 0

                    ApiCommandButton {
                        buttonText: Translation.tr("clear")
                        downAction: () => {
                            messageInputField.text = "";
                            messageListModel.clear();
                            root.agentPromptCount = 0;
                            messageInputField.forceActiveFocus();
                        }
                    }

                    ApiCommandButton {
                        buttonText: Translation.tr("status")
                        downAction: () => root.runHermesCommand(Translation.tr("Hermes status"), "status")
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        z: 20
        visible: root.showingOllamaManager
        color: Appearance.colors.colLayer1

        ColumnLayout {
            anchors {
                fill: parent
                margins: root.padding
            }
            spacing: root.padding

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: ollamaHeaderRow.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: ollamaHeaderRow
                    anchors {
                        fill: parent
                        margins: 8
                    }
                    spacing: 8

                    MaterialSymbol {
                        text: "memory"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Ollama models")
                        color: Appearance.colors.colOnLayer2
                        font.bold: true
                    }

                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer3
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        onClicked: {
                            root.showingOllamaManager = false;
                            Qt.callLater(root.focusActiveItem);
                        }

                        contentItem: MaterialSymbol {
                            text: "close"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer3
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Loader {
                id: ollamaManagerLoader
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.showingOllamaManager
                asynchronous: true
                sourceComponent: Component {
                    OllamaModels {}
                }
                onLoaded: Qt.callLater(root.focusActiveItem)
            }
        }
    }

    component RouteChip: Rectangle {
        id: chip
        property string chipIcon
        required property string chipText
        property bool primary: false

        implicitHeight: chipContent.implicitHeight + 8
        implicitWidth: Math.min(chipContent.implicitWidth + 12, 220)
        radius: Appearance.rounding.full
        color: primary ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3

        RowLayout {
            id: chipContent
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                text: chip.chipIcon
                iconSize: 14
                color: chip.primary ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
            }

            StyledText {
                Layout.maximumWidth: 180
                text: chip.chipText
                color: chip.primary ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideRight
            }
        }
    }

    component HarnessActionButton: RippleButton {
        id: actionButton
        property string buttonIcon
        property string label
        property string tooltip
        property var triggerAction

        implicitWidth: Math.max(actionContent.implicitWidth + 16, 44)
        implicitHeight: 30
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        onClicked: {
            if (actionButton.triggerAction)
                actionButton.triggerAction();
        }

        contentItem: RowLayout {
            id: actionContent
            spacing: 5

            MaterialSymbol {
                text: actionButton.buttonIcon
                iconSize: 16
                color: Appearance.colors.colOnLayer2
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: actionButton.label
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.small
                Layout.alignment: Qt.AlignVCenter
            }
        }

        StyledToolTip {
            text: actionButton.tooltip
        }
    }

    component InlineSwitch: RippleButton {
        id: inlineSwitch
        property string buttonIcon
        property string label
        property bool switchChecked: false

        implicitWidth: inlineContent.implicitWidth + 12
        implicitHeight: 28
        buttonRadius: Appearance.rounding.small
        toggled: switchChecked
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colBackgroundToggled: Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: Appearance.colors.colPrimaryContainer
        onClicked: switchChecked = !switchChecked

        contentItem: RowLayout {
            id: inlineContent
            spacing: 4

            MaterialSymbol {
                text: inlineSwitch.buttonIcon
                iconSize: 15
                color: inlineSwitch.switchChecked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
            }

            StyledText {
                text: inlineSwitch.label
                color: inlineSwitch.switchChecked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}
