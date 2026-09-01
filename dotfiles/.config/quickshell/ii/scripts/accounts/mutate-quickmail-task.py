#!/usr/bin/env python3
"""Perform one provider-neutral QuickMail task mutation.

The task payload travels as one argv value, so titles and descriptions are
never interpreted by a shell. QuickMail remains responsible for account
capabilities, durable operations, synchronization, and credentials.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ALLOWED_METHODS = {"task.create", "task.complete", "task.delete"}


def quickmailctl_path():
    override = os.environ.get("QUICKMAILCTL", "").strip()
    candidates = [
        Path(override) if override else None,
        Path(shutil.which("quickmailctl")) if shutil.which("quickmailctl") else None,
        Path.home() / "QuickMail/target/release/quickmailctl",
        Path.home() / "QuickMail/target/debug/quickmailctl",
    ]
    return next((path for path in candidates if path and path.is_file() and os.access(path, os.X_OK)), None)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("method", choices=sorted(ALLOWED_METHODS))
    parser.add_argument("payload")
    args = parser.parse_args()

    payload = json.loads(args.payload)
    if not isinstance(payload, dict):
        raise ValueError("QuickMail mutation payload must be a JSON object")

    binary = quickmailctl_path()
    if binary is None:
        raise RuntimeError("quickmailctl is not available")

    result = subprocess.run(
        [
            str(binary),
            "--compact",
            "raw",
            args.method,
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        ],
        capture_output=True,
        check=False,
        text=True,
        # Provider mutations may legitimately wait for the daemon's 90-second
        # upstream timeout. Leave enough room to receive its structured error.
        timeout=120,
    )
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()
        raise RuntimeError(detail[-1] if detail else f"quickmailctl exited with code {result.returncode}")

    response = json.loads(result.stdout or "{}")
    print(json.dumps(response, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
