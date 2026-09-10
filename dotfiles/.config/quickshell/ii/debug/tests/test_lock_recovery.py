#!/usr/bin/env python3
"""Exercise lock recovery across real, isolated Quickshell processes."""

import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import tempfile
import unittest


LOCK_MODULE = Path(__file__).resolve().parents[2] / "modules/common/panels/lock"
QS = os.environ.get("QS_BIN") or shutil.which("qs") or shutil.which("quickshell")


@unittest.skipUnless(QS, "Quickshell is required")
class LockRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="quickshell-lock-test-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        shutil.copy2(LOCK_MODULE / "LockRecovery.qml", self.directory)
        self.env = dict(os.environ, QT_QPA_PLATFORM="offscreen",
                        XDG_RUNTIME_DIR=self.temp.name, QML_DISABLE_DISK_CACHE="1")
        self.env.pop("WAYLAND_DISPLAY", None)
        self.env.pop("DISPLAY", None)

    def run_shell(self, action="read", signature="test-session"):
        shell = self.directory / "shell.qml"
        shell.write_text(f'''
import QtQuick
import Quickshell

ShellRoot {{
    LockRecovery {{ id: recovery }}
    Timer {{
        interval: 1
        running: recovery.ready
        onTriggered: {{
            console.info("RESTORE=" + recovery.restoreRequested);
            const action = {json.dumps(action)};
            if (action === "lock" || action === "crash")
                recovery.setLocked(true);
            else if (action === "unlock")
                recovery.setLocked(false);
            console.info("PROBE_READY");
        }}
    }}
}}
''')
        env = dict(self.env, HYPRLAND_INSTANCE_SIGNATURE=signature)
        with subprocess.Popen([QS, "--no-color", "-p", str(shell)], env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as process:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                output = ""
                try:
                    while "PROBE_READY" not in output:
                        self.assertTrue(selector.select(10), output)
                        chunk = os.read(process.stdout.fileno(), 65536).decode()
                        self.assertTrue(chunk, output)
                        output += chunk
                finally:
                    if action == "crash":
                        # Kill immediately after the synchronous state write.
                        process.kill()
                    else:
                        process.terminate()
                    process.wait(timeout=5)
            if action == "crash":
                self.assertEqual(process.returncode, -signal.SIGKILL)
            else:
                self.assertIn(process.returncode, (0, -signal.SIGTERM))
        self.assertNotIn("Failed to load configuration", output)
        self.assertIn("RESTORE=", output)
        return "RESTORE=true" in output

    def test_crash_restores_only_the_same_compositor(self):
        self.assertFalse(self.run_shell("crash"))
        self.assertTrue(self.run_shell())
        self.assertFalse(self.run_shell(signature="new-session"))
        self.assertTrue(self.run_shell())

    def test_completed_unlock_clears_recovery(self):
        self.assertFalse(self.run_shell("lock"))
        self.assertTrue(self.run_shell("unlock"))
        self.assertFalse(self.run_shell())

    def test_missing_session_does_not_create_shared_state(self):
        self.assertFalse(self.run_shell("lock", signature=""))
        self.assertFalse(self.run_shell(signature=""))


if __name__ == "__main__":
    unittest.main()
