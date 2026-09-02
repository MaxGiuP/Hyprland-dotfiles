#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import os
import pty
import time
import unittest
from pathlib import Path


HELPER_PATH = Path(__file__).resolve().parents[1] / "broadcast_terminal_colors.py"
SPEC = importlib.util.spec_from_file_location("broadcast_terminal_colors", HELPER_PATH)
assert SPEC is not None and SPEC.loader is not None
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


class BroadcastTerminalColorsTest(unittest.TestCase):
    def test_writes_to_owned_pty(self) -> None:
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        path = os.ttyname(slave)
        payload = b"\x1b]4;0;rgb:12/34/56\x07"

        updated, written = HELPER.broadcast(payload, [path])

        self.assertEqual(updated, 1)
        self.assertEqual(written, len(payload))
        self.assertEqual(os.read(master, len(payload)), payload)

    def test_full_unread_pty_returns_immediately(self) -> None:
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        path = os.ttyname(slave)
        os.set_blocking(slave, False)

        chunk = b"x" * 65536
        while True:
            try:
                os.write(slave, chunk)
            except BlockingIOError:
                break

        started = time.monotonic()
        updated, written = HELPER.broadcast(b"terminal-colours", [path])
        elapsed = time.monotonic() - started

        self.assertEqual((updated, written), (0, 0))
        self.assertLess(elapsed, 0.1)

    def test_rejects_non_pty_path(self) -> None:
        self.assertEqual(HELPER.write_terminal("/dev/null", b"colours"), 0)


if __name__ == "__main__":
    unittest.main()
