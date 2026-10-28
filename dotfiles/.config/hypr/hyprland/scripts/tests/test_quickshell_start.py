"""Check the renderer selected by the real Quickshell service launcher."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]


class QuickshellStartTest(unittest.TestCase):
    def launch(self, render_loop=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            launcher = root / "start_quickshell.sh"
            shutil.copy2(SCRIPTS / launcher.name, launcher)
            for name in ("quickshell_event_log.sh", "quickshell_compat_check.sh"):
                stub = root / name
                stub.write_text("#!/bin/sh\nexit 0\n")
                stub.chmod(0o755)
            binary = root / "qs"
            binary.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "print(json.dumps({'loop': os.environ.get('QSG_RENDER_LOOP'), "
                "'args': sys.argv[1:]}))\n"
            )
            binary.chmod(0o755)
            env = dict(os.environ, HOME=directory, QS_BIN=str(binary),
                       WAIT_FOR_HYPR_TENTHS="0", WAIT_FOR_WIREPLUMBER_TENTHS="0")
            env.pop("QSG_RENDER_LOOP", None)
            if render_loop is not None:
                env["QSG_RENDER_LOOP"] = render_loop
            result = subprocess.run([str(launcher), "fixture"], env=env,
                                    capture_output=True, text=True, timeout=5,
                                    check=True)
            return json.loads(result.stdout)

    def test_service_defaults_to_basic_render_loop(self):
        result = self.launch()
        self.assertEqual(result["loop"], "basic")
        self.assertEqual(result["args"], ["--no-duplicate", "-c", "fixture"])

    def test_explicit_render_loop_is_preserved(self):
        self.assertEqual(self.launch("threaded")["loop"], "threaded")


if __name__ == "__main__":
    unittest.main()
