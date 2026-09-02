#!/usr/bin/env python3
"""Send generated terminal colours to owned PTYs without ever blocking."""

from __future__ import annotations

import argparse
import glob
import os
import re
import stat
import sys
from pathlib import Path
from typing import Iterable


PTY_PATTERN = re.compile(r"^/dev/pts/[0-9]+$")


def discover_terminals() -> list[str]:
    """Return numeric PTY slaves in a stable order."""
    paths = (path for path in glob.glob("/dev/pts/[0-9]*") if PTY_PATTERN.fullmatch(path))
    return sorted(paths, key=lambda path: int(path.rsplit("/", 1)[1]))


def write_terminal(path: str, payload: bytes, uid: int | None = None) -> int:
    """Attempt one non-blocking write, returning the number of bytes accepted."""
    if not payload or not PTY_PATTERN.fullmatch(path):
        return 0

    expected_uid = os.getuid() if uid is None else uid
    flags = os.O_WRONLY | os.O_NONBLOCK | os.O_NOCTTY
    flags |= getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)

    fd: int | None = None
    try:
        path_stat = os.lstat(path)
        if not stat.S_ISCHR(path_stat.st_mode) or path_stat.st_uid != expected_uid:
            return 0

        fd = os.open(path, flags)
        fd_stat = os.fstat(fd)
        if not stat.S_ISCHR(fd_stat.st_mode) or fd_stat.st_uid != expected_uid:
            return 0

        # A single O_NONBLOCK write is deliberately used here. Retrying a full
        # PTY is what allowed the previous `cat > /dev/pts/N` jobs to pile up.
        return os.write(fd, payload)
    except OSError:
        return 0
    finally:
        if fd is not None:
            os.close(fd)


def broadcast(payload: bytes, terminals: Iterable[str] | None = None) -> tuple[int, int]:
    """Return (terminals updated, bytes accepted) for this bounded pass."""
    updated = 0
    bytes_written = 0
    for terminal in discover_terminals() if terminals is None else terminals:
        written = write_terminal(str(terminal), payload)
        if written:
            updated += 1
            bytes_written += written
    return updated, bytes_written


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sequences", type=Path, help="generated terminal escape-sequence file")
    parser.add_argument(
        "--terminal",
        action="append",
        dest="terminals",
        help="write only to this PTY (repeatable; primarily useful for testing)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        payload = args.sequences.read_bytes()
    except OSError as error:
        print(f"Unable to read terminal colour sequences: {error}", file=sys.stderr)
        return 1

    broadcast(payload, args.terminals)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
