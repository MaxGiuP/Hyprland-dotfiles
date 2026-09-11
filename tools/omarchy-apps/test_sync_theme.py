"""Run with: python3 -B -m unittest discover -s tools/omarchy-apps -p 'test_*.py'."""

import importlib.util
import configparser
from pathlib import Path
import tempfile
import tomllib
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("sync_theme", Path(__file__).with_name("sync-theme.py"))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

PALETTE = {
    "background": "#131318",
    "on_surface": "#e4e1e9",
    "primary": "#BFC2FF",
    "on_surface_variant": "#c7c5d0",
    "error": "#ffb4ab",
    "surface_container_low": "#1b1b21",
    "tertiary": "#e8b9d4",
}


class ThemeBridgeTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.state = self.root / "omarchy/current"
        self.rendered = bridge.render(PALETTE, {})

    def test_maps_material_roles_and_flea_aliases(self):
        colors = tomllib.loads(self.rendered["colors.toml"])
        for target, source in {
            "background": "background", "foreground": "on_surface", "accent": "primary",
            "muted": "on_surface_variant", "red": "error", "color1": "error",
            "dark_background": "surface_container_low", "cyan": "tertiary", "color6": "tertiary",
        }.items():
            self.assertEqual(PALETTE[source].lower(), colors[target])
        self.assertEqual("#a6e3a1", colors["green"])
        self.assertEqual(colors["green"], colors["color2"])
        self.assertEqual({"font": {"base-size": 14}}, tomllib.loads(self.rendered["shell.toml"]))

    def test_fallback_foreground_and_config(self):
        palette = dict(PALETTE)
        del palette["on_surface"]
        palette["on_background"] = "#123456"
        rendered = bridge.render(palette, {"font": {"base-size": 16}, "palette": {"green": "#abcdef"}})
        colors = tomllib.loads(rendered["colors.toml"])
        self.assertEqual("#123456", colors["foreground"])
        self.assertEqual("#abcdef", colors["green"])
        self.assertEqual(16, tomllib.loads(rendered["shell.toml"])["font"]["base-size"])
        palette["green"] = "#654321"
        self.assertEqual("#654321", tomllib.loads(bridge.render(palette, {})["colors.toml"])["green"])

    def test_rejects_invalid_or_missing_palette_roles(self):
        for value in ("#abc", "#123456ff", "112233", "#xyzxyz", 123, None, "#123456\n"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                bridge.render({**PALETTE, "background": value}, {})
        with self.assertRaises(ValueError):
            bridge.render({"background": "#123456"}, {})
        with self.assertRaises(ValueError):
            bridge.render([], {})

    def test_rejects_invalid_config(self):
        for config in ({"font": {"base-size": 0}}, {"font": {"base-size": True}},
                       {"font": {"base-size": 14.5}}, {"font": {"family": "ignored"}},
                       {"palette": {"green": "#abc"}}, {"typo": {}}, {"font": "bad"}):
            with self.subTest(config=config), self.assertRaises(ValueError):
                bridge.render(PALETTE, config)

    def test_check_writes_nothing(self):
        self.assertEqual(["colors.toml", "shell.toml"], bridge.sync(self.state, self.rendered, check=True))
        self.assertFalse(self.state.parent.exists())

    def test_first_run_and_noop(self):
        self.assertEqual(["colors.toml", "shell.toml"], bridge.sync(self.state, self.rendered))
        self.assertEqual(bridge.OWNER, (self.state / "theme" / bridge.OWNER_FILE).read_text())
        watched = self.state / "theme.name"
        before = watched.stat()
        self.assertEqual(bridge.THEME_NAME, watched.read_text())
        self.assertEqual([], bridge.sync(self.state, self.rendered))
        self.assertEqual(before.st_mtime_ns, watched.stat().st_mtime_ns)
        self.assertEqual(before.st_ino, watched.stat().st_ino)

    def test_color_files_replaced_before_watched_name_changes(self):
        bridge.sync(self.state, self.rendered)
        watched = self.state / "theme.name"
        before = watched.stat()
        old_color_inode = (self.state / "theme/colors.toml").stat().st_ino
        updated = bridge.render({**PALETTE, "primary": "#123456"}, {"font": {"base-size": 16}})
        replace = bridge.atomic_write
        replaced = []

        def observe_replace(path, body):
            self.assertEqual(before.st_mtime_ns, watched.stat().st_mtime_ns)
            replace(path, body)
            replaced.append(path.name)

        with patch.object(bridge, "atomic_write", side_effect=observe_replace):
            bridge.sync(self.state, updated)
        self.assertEqual(["colors.toml", "shell.toml"], replaced)
        self.assertEqual(before.st_ino, watched.stat().st_ino)
        self.assertNotEqual(old_color_inode, (self.state / "theme/colors.toml").stat().st_ino)
        self.assertEqual(updated["colors.toml"], (self.state / "theme/colors.toml").read_text())
        self.assertEqual(updated["shell.toml"], (self.state / "theme/shell.toml").read_text())

    def test_refuses_unowned_theme_even_when_empty(self):
        (self.state / "theme").mkdir(parents=True)
        for check in (True, False):
            with self.subTest(check=check), self.assertRaisesRegex(ValueError, "not owned"):
                bridge.sync(self.state, self.rendered, check=check)
        self.assertEqual([], list((self.state / "theme").iterdir()))

    def test_refuses_existing_theme_name_without_owned_theme(self):
        self.state.mkdir(parents=True)
        (self.state / "theme.name").write_text("Another theme\n")
        with self.assertRaisesRegex(ValueError, "without a bridge-owned theme"):
            bridge.sync(self.state, self.rendered)
        self.assertEqual("Another theme\n", (self.state / "theme.name").read_text())

    def test_refuses_external_theme_switch(self):
        bridge.sync(self.state, self.rendered)
        (self.state / "theme.name").write_text("Another theme\n")
        with self.assertRaisesRegex(ValueError, "another theme manager"):
            bridge.sync(self.state, self.rendered)

    def test_refuses_theme_symlink(self):
        self.state.mkdir(parents=True)
        target = self.root / "existing-theme"
        target.mkdir()
        (self.state / "theme").symlink_to(target, target_is_directory=True)
        with self.assertRaises(ValueError):
            bridge.sync(self.state, self.rendered)
        self.assertEqual([], list(target.iterdir()))

    def test_refuses_output_file_symlink(self):
        bridge.sync(self.state, self.rendered)
        target = self.root / "untouched"
        target.write_text("keep\n")
        (self.state / "theme/colors.toml").unlink()
        (self.state / "theme/colors.toml").symlink_to(target)
        with self.assertRaises(ValueError):
            bridge.sync(self.state, self.rendered)
        self.assertEqual("keep\n", target.read_text())

    def test_refuses_state_ancestor_symlink(self):
        self.state.parent.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            bridge.sync(self.state, self.rendered)
        self.assertFalse((self.root / "current").exists())


class ThemeWatcherTest(unittest.TestCase):
    def setUp(self):
        self.units = Path(__file__).resolve().parents[2] / "dotfiles/.config/systemd/user"

    def test_path_only_watches_inputs_after_close(self):
        body = (self.units / "omarchy-apps-theme-sync.path").read_text()
        directives = [line for line in body.splitlines() if line.startswith("Path")]
        self.assertEqual([
            "PathChanged=%h/.local/state/quickshell/user/generated/colors.json",
            "PathChanged=%h/.config/omarchy-apps/theme.toml",
        ], directives)

    def test_service_is_bounded_oneshot_with_matching_inputs(self):
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        parser.read(self.units / "omarchy-apps-theme-sync.service")
        service = parser["Service"]
        self.assertEqual("oneshot", service["Type"])
        self.assertEqual("no", service["Restart"])
        self.assertEqual("15s", service["TimeoutStartSec"])
        self.assertEqual(
            "/usr/bin/python3 -B %h/.local/share/omarchy-apps/bin/sync-theme.py --quiet "
            "--source=%h/.local/state/quickshell/user/generated/colors.json "
            "--config=%h/.config/omarchy-apps/theme.toml", service["ExecStart"])
        self.assertNotIn("Install", parser)


if __name__ == "__main__":
    unittest.main()
