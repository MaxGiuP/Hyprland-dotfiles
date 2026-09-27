// Synthetic checks only: no desktop screen/audio capture and no network calls.
// Run: node --test scripts/tests/live_services.test.cjs
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');

function service(name, directory = '/tmp/live-service-test') {
    const source = fs.readFileSync(path.join(__dirname, '../../services', name + '.qml'), 'utf8');
    const kind = name === 'LiveCaptions' ? 'liveCaptions' : 'liveScreenTranslation';
    const timer = () => ({ running: false, interval: 0,
        restart() { this.running = true; }, stop() { this.running = false; } });
    const settings = { desiredRunning: false };
    const root = {
        backendAvailable: true, backendChecked: true, backendKind: 'whisper',
        sourceMode: 'system', displayMode: 'bilingual', preferredLanguage: 'auto',
        targetLanguage: 'en', modelName: 'tiny', tuningPreset: 'realtime',
        region: '-1920,0 800x600', regionLabel: '', ocrLanguage: 'eng',
        workerActive: false, launchPending: false, stopRequested: false,
        restartPending: false, recoveryAttempts: 0, workerGeneration: 0,
        state: {}, selectingRegion: false,
        Persistent: { ready: true, states: { [kind]: settings } },
        Translation: { tr: text => text },
        CaptionAppearance: { translationGranularity: 'phrase' },
        Appearance: { colors: { colOnSurfaceVariant: '#202020' } },
        CF: { StringUtils: { shellSingleQuoteEscape: value => String(value).replaceAll("'", "'\\''") } },
        Directories: {}, GlobalStates: { overlayOpen: true },
        workerStatusProc: { running: false, generation: -1 },
        workerLaunchProc: { running: false }, workerStopProc: { running: false },
        regionSelectionProc: { running: false }, backendProbe: { running: false },
        stateFileView: { reload() {}, text() { return '{}'; } },
    };
    Object.defineProperties(root, {
        active: { get() { return this.workerActive || this.launchPending || this.recoveryTimer.running || this.stopRequested; } },
        desiredRunning: { get() { return settings.desiredRunning; } },
        translating: { get() { return this.displayMode !== 'captions'; } },
        status: { get() { return this.state.status || 'stopped'; } },
        statusMessage: { get() { return this.state.message || ''; } },
    });
    for (const id of ['recoveryTimer', 'restartTimer', 'stableWorkerTimer', 'launchTimeoutTimer', 'initialWorkerProbeTimer'])
        root[id] = timer();
    for (const [suffix, filename] of Object.entries({
        StatePath: 'state.json', PidPath: 'backend.pid', LogPath: 'backend.log',
        BackendScriptPath: 'backend.py', PythonPath: 'missing-python', VenvPath: 'venv', ModelCachePath: 'models',
    })) root.Directories[kind + suffix] = path.join(directory, filename);
    root.root = root;
    const context = vm.createContext(root);
    for (const match of source.matchAll(/^    function (\w+)\([^\n]*\) \{.*?^    }$/gms))
        vm.runInContext(match[0], context);
    root.exit = (id, code = 0) => {
        root[id].running = false;
        const block = source.match(new RegExp(`    Process \\{\\n        id: ${id}\\n.*?\\n    }`, 's'))?.[0];
        const body = block?.match(/onExited: \(exitCode, exitStatus\) => \{(.*?)\n        }/s)?.[1];
        assert.ok(body, `exit handler for ${id}`);
        root.generation = root[id].generation;
        vm.runInContext(`(function(exitCode, exitStatus) {${body}\n})(${code}, 0)`, context);
    };
    return root;
}

for (const name of ['LiveCaptions', 'LiveScreenTranslation']) {
    test(`${name}: manual stop cancels queued configuration/recovery starts`, () => {
        const s = service(name);
        s.Persistent.states[name === 'LiveCaptions' ? 'liveCaptions' : 'liveScreenTranslation'].desiredRunning = true;
        s.workerActive = true;
        s.restartIfActive();
        assert.equal(s.restartTimer.running, true);
        s.stop();
        assert.equal(s.restartTimer.running, false);
        assert.equal(s.recoveryTimer.running, false);
        assert.equal(s.restartPending, false);
        s.exit('workerStopProc');
        s.start(true); // A recovery callback already queued before Stop is harmless.
        assert.equal(s.workerLaunchProc.running, false);
        assert.equal(s.active, false);
    });

    test(`${name}: stop waits for launch PID and restart waits for completed stop`, () => {
        const s = service(name);
        s.start();
        assert.equal(s.workerLaunchProc.running, true);
        s.stop();
        assert.equal(s.workerStopProc.running, false);
        s.start(); // Explicit Start while stopping queues a fresh run.
        assert.equal(s.restartPending, true);
        s.exit('workerLaunchProc');
        assert.equal(s.workerStopProc.running, true);
        assert.equal(s.workerLaunchProc.running, false);
        s.exit('workerStopProc');
        assert.equal(s.workerLaunchProc.running, true);
        assert.equal(s.restartPending, false);
    });

    test(`${name}: stale probes cannot resurrect a stopped worker`, () => {
        const s = service(name);
        s.probeWorker();
        s.stop();
        s.exit('workerStopProc');
        s.exit('workerStatusProc', 0);
        assert.equal(s.active, false);
    });

    test(`${name}: a slow old worker blocks replacement`, () => {
        const s = service(name);
        s.start();
        s.exit('workerLaunchProc');
        s.updateWorkerState(true);
        s.restartIfActive();
        s.stop(true);
        s.exit('workerStopProc', 1);
        assert.equal(s.workerLaunchProc.running, false);
        assert.equal(s.workerActive, true);
        assert.equal(s.status, 'error');
    });

    test(`${name}: launch/state/stop commands work with a harmless worker`, () => {
        const directory = fs.mkdtempSync(path.join(os.tmpdir(), "live-service-'quote-"));
        const s = service(name, directory);
        const pidPath = path.join(directory, 'backend.pid');
        const statePath = path.join(directory, 'state.json');
        fs.writeFileSync(path.join(directory, 'backend.py'), `import json, pathlib, signal, sys, time\np = pathlib.Path(sys.argv[sys.argv.index('--state-file') + 1])\nrunning = True\ndef stop(*args):\n    global running\n    running = False\nsignal.signal(signal.SIGTERM, stop)\np.write_text(json.dumps({'status':'running', 'message':'synthetic worker'}))\nwhile running:\n    time.sleep(.01)\ntime.sleep(.25)\np.write_text(json.dumps({'status':'stopped', 'message':'last worker write'}))\n`);
        const run = command => {
            const result = spawnSync(command[0], command.slice(1), { encoding: 'utf8', timeout: 15000 });
            assert.equal(result.status, 0, result.stderr || String(result.error || 'command failed'));
        };
        try {
            s.clearState('loading');
            run(s.buildBackendLaunchCommand());
            const pid = fs.readFileSync(pidPath, 'utf8');
            // Wait for only the synthetic worker's first update.
            run(['python3', '-c', "import json,pathlib,sys,time; p=pathlib.Path(sys.argv[1]); deadline=time.monotonic()+3\nwhile json.loads(p.read_text()).get('status')!='running':\n assert time.monotonic()<deadline\n time.sleep(.01)", statePath]);
            run(s.buildWorkerStatusCommand());
            run(s.buildBackendLaunchCommand());
            assert.equal(fs.readFileSync(pidPath, 'utf8'), pid, 'launch must retain an existing worker');
            assert.equal(JSON.parse(fs.readFileSync(statePath)).status, 'running', 'duplicate launch must retain live state');
            s.clearState('stopped', 'service stopped');
            const before = Date.now();
            run(s.buildStopCommand());
            assert.ok(Date.now() - before >= 200, 'stop waits for graceful worker cleanup');
            assert.equal(fs.existsSync(pidPath), false);
            assert.equal(JSON.parse(fs.readFileSync(statePath)).message, 'service stopped', 'final UI state follows worker exit');
            assert.equal(fs.statSync(statePath).mode & 0o777, 0o600);
            // A corrupted PID must never be interpreted as a process group.
            fs.writeFileSync(pidPath, '-1\n');
            run(s.buildStopCommand());
        } finally {
            if (fs.existsSync(pidPath)) {
                const pid = Number(fs.readFileSync(pidPath, 'utf8'));
                if (Number.isInteger(pid) && pid > 1) { try { process.kill(pid, 'SIGKILL'); } catch {} }
            }
            fs.rmSync(directory, { recursive: true, force: true });
        }
    });
}

test('screen geometry supports negative monitors and validates dimensions', () => {
    const s = service('LiveScreenTranslation');
    for (const geometry of ['-1920,-1080 800x600', '+1920,0 10x20', '-.5,2.5 .2x1.5'])
        assert.equal(s.isValidGeometry(geometry), true, geometry);
    for (const geometry of ['0,0 0x100', '0,0 2x0', '0,0 -2x3', '..,0 1x3', '0,0 1..2x3', '0,0 2x3; echo bad'])
        assert.equal(s.isValidGeometry(geometry), false, geometry);
    assert.equal(s.normalizedGeometry('-.5,2.5 .2x1.5'), '0,2 1x2');
});

test('caption state excludes stale target translations and invalid history', () => {
    const s = service('LiveCaptions');
    s.clearState();
    s.handleStatePayload({ target_language: 'fr', translated_text: 'old target' });
    assert.equal(s.state.translated_text, '');
    s.handleStatePayload({ target_language: 'en', history: 'bad' });
    assert.equal(Array.isArray(s.state.history), true);
    assert.throws(() => s.handleStatePayload(null), /Invalid caption state/);
});

test('tentative captions use the current theme and escape rich text', () => {
    const s = service('LiveCaptions');
    s.visibleStableText = 'one <two>';
    s.visibleUnstableText = '<b>& three';
    assert.match(s.sourceCaptionMarkup(), /color:#202020/);
    assert.match(s.sourceCaptionMarkup(), /&lt;b&gt;&amp;/);
    s.Appearance.colors.colOnSurfaceVariant = '#eeeeee';
    assert.match(s.sourceCaptionMarkup(), /color:#eeeeee/);
});

for (const name of ['LiveCaptions', 'LiveScreenTranslation']) {
    test(`${name}: passes selected translation granularity to its worker`, () => {
        const s = service(name);
        for (const mode of ['phrase', 'sentence']) {
            s.CaptionAppearance.translationGranularity = mode;
            assert.ok(s.buildBackendLaunchCommand()[2].includes(`--translation-granularity '${mode}'`));
        }
    });
}
