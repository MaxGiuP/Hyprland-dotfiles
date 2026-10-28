#!/usr/bin/env python3
"""Exercise resume scripts with isolated commands, never the live desktop."""

import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]


class ResumeIpcTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.ipc_log = self.directory / "ipc.log"
        self.env = os.environ | {
            "HOME": str(self.directory),
            "XDG_CACHE_HOME": str(self.directory / "cache"),
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "QS_BIN": str(self.bin / "qs"),
            "QS_IPC_TIMEOUT": "0.02",
            "WAIT_FOR_IPC_TENTHS": "1",
            "IPC_LOG": str(self.ipc_log),
            "QS_STUB_HANG": "0",
            "ENSURE_STATUS": "0",
        }
        self.write_executable(self.bin / "sleep", "#!/bin/sh\nexit 0\n")
        self.write_executable(self.bin / "systemctl", "#!/bin/sh\nexit 0\n")
        self.write_executable(self.bin / "qs", """#!/bin/sh
printf '%s\\n' "$*" >> "$IPC_LOG"
if [ "$QS_STUB_HANG" = 1 ]; then
    exec /bin/sleep 30
fi
case "$*" in
    *'ipc call health ping'|*'ipc call lock focus') exit 0 ;;
    *) exit 1 ;;
esac
""")
        self.write_executable(self.directory / "quickshell_event_log.sh", "#!/bin/sh\nexit 0\n")
        self.write_executable(self.directory / "quickshell_compat_check.sh", "#!/bin/sh\nexit 0\n")
        recovery = self.directory / ".local/libexec/quickshell-resume-recovery.py"
        recovery.parent.mkdir(parents=True)
        recovery.write_text("raise SystemExit(0)\n")

    def write_executable(self, path, contents):
        path.write_text(contents)
        path.chmod(0o755)

    def run_script(self, name):
        target = self.directory / name
        shutil.copy2(SCRIPTS / name, target)
        process = subprocess.Popen(
            ["/bin/sh", str(target)], env=self.env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, start_new_session=True,
        )
        try:
            stdout, stderr = process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            self.fail(f"{name} blocked on an unresponsive IPC command")
        return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)

    def stub_ensure(self):
        self.write_executable(
            self.directory / "ensure_quickshell.sh",
            '#!/bin/sh\nexit "$ENSURE_STATUS"\n',
        )

    def test_hanging_resume_focus_is_bounded(self):
        self.stub_ensure()
        self.env["QS_STUB_HANG"] = "1"
        result = self.run_script("on-resume.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ipc call lock focus", self.ipc_log.read_text())

    def test_failed_ensure_still_focuses_and_preserves_failure_status(self):
        self.stub_ensure()
        self.env["ENSURE_STATUS"] = "7"
        result = self.run_script("on-resume.sh")
        calls = self.ipc_log.read_text() if self.ipc_log.exists() else ""
        self.assertIn("ipc call lock focus", calls)
        self.assertEqual(result.returncode, 7, result.stderr)

    def test_successful_resume_focuses(self):
        self.stub_ensure()
        result = self.run_script("on-resume.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ipc call lock focus", self.ipc_log.read_text())

    def test_readiness_uses_health_without_changing_focus(self):
        result = self.run_script("ensure_quickshell.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.ipc_log.read_text()
        self.assertIn("ipc call health ping", calls)
        self.assertNotIn("ipc call lock focus", calls)


if __name__ == "__main__":
    unittest.main()
