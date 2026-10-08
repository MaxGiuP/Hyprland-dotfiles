import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("monitor_layout", Path(__file__).parents[1] / "monitor-layout.py")
layout = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(layout)


def rule(output, position="0x0", transform=0):
    return dict(output=output, mode="1920x1080@60.00", position=position,
                scale=1, transform=transform)


class MonitorLayoutTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "monitor_layout.lua"
        self.original = layout.render_layout(layout.validate_rules([
            rule("DP-1", "1920x0"), rule("HDMI-A-1", "0x180"), rule("DP-2", "-1080x-200", 3),
        ]))
        self.path.write_text(self.original)

    def assert_original_preserved(self):
        self.assertEqual(self.path.read_text(), self.original)
        self.assertEqual(list(self.path.parent.glob(".monitor-layout-*")), [])

    def test_partial_save_preserves_other_and_disconnected_displays(self):
        update = rule("HDMI-A-1", "840x-120", 1)
        update["scale"] = 1.5
        with patch.object(layout.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "ok\n", "")) as run:
            layout.apply_and_save(self.path, [update])
        saved = layout.read_layout(self.path)
        self.assertEqual(saved["HDMI-A-1"], update)
        self.assertEqual(saved["DP-1"], rule("DP-1", "1920x0"))
        self.assertEqual(saved["DP-2"], rule("DP-2", "-1080x-200", 3))
        command = run.call_args.args[0]
        self.assertEqual(command[:2], ["hyprctl", "eval"])
        self.assertIn("transform = 1", command[2])
        self.assertNotIn("DP-2", command[2])
        self.assertEqual(list(self.path.parent.glob(".monitor-layout-*")), [])

    def test_zero_exit_compositor_error_does_not_save(self):
        with patch.object(layout.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "Lua error: invalid mode\n", "")):
            with self.assertRaisesRegex(RuntimeError, "invalid mode"):
                layout.apply_and_save(self.path, [rule("DP-1")])
        self.assert_original_preserved()

    def test_compositor_timeout_does_not_save(self):
        with patch.object(layout.subprocess, "run", side_effect=subprocess.TimeoutExpired("hyprctl", 15)):
            with self.assertRaises(subprocess.TimeoutExpired):
                layout.apply_and_save(self.path, [rule("DP-1")])
        self.assert_original_preserved()

    def test_invalid_batch_is_rejected_before_applying_any_display(self):
        invalid = rule("HDMI-A-1", transform=8)
        with patch.object(layout.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "orientation"):
                layout.apply_and_save(self.path, [rule("DP-1"), invalid])
        run.assert_not_called()
        self.assert_original_preserved()

    def test_manual_edits_are_preserved(self):
        self.path.write_text(self.original.replace("transform = 0", "transform = 2"))
        manual = self.path.read_text()
        with patch.object(layout.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "edited manually"):
                layout.apply_and_save(self.path, [rule("DP-1")])
        run.assert_not_called()
        self.assertEqual(self.path.read_text(), manual)

    def test_disk_failure_reports_temporary_application_without_truncating_config(self):
        with patch.object(layout.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "ok\n", "")):
            with patch.object(layout.os, "replace", side_effect=OSError("disk full")):
                with self.assertRaisesRegex(RuntimeError, "applied temporarily.*disk full"):
                    layout.apply_and_save(self.path, [rule("DP-1")])
        self.assert_original_preserved()


if __name__ == "__main__":
    unittest.main()
