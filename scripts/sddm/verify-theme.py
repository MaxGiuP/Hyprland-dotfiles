#!/usr/bin/env python3
"""Load an SDDM theme in a background greeter and reject fallback/errors."""

import argparse
import os
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("theme", type=Path)
    parser.add_argument("--platform", choices=("offscreen", "xcb"), default="offscreen")
    args = parser.parse_args()
    theme = args.theme.resolve(strict=True)
    env = os.environ.copy()
    env.update(
        QT_QPA_PLATFORM=args.platform,
        QT_QUICK_BACKEND="software",
        QT_LOGGING_TO_CONSOLE="1",
        QT_FORCE_STDERR_LOGGING="1",
    )
    process = subprocess.Popen(
        ["sddm-greeter-qt6", "--test-mode", "--theme", str(theme)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )
    stopped_by_test = False
    try:
        output, _ = process.communicate(timeout=6)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            output, _ = process.communicate(timeout=3)
            stopped_by_test = True
        except subprocess.TimeoutExpired:
            process.kill()
            output, _ = process.communicate()

    print(output, end="")
    print(f"Greeter exit status: {process.returncode}")
    failures = re.findall(
        r"^.*(?:Fallback to embedded theme|is not a type|is not available|"
        r"Type \S+ unavailable|Cannot assign to non-existent property|"
        r"ReferenceError:|TypeError:).*$",
        output,
        flags=re.MULTILINE,
    )
    loaded = (
        f"Loading file://{theme}/Main.qml" in output
        and "Adding view for" in output
        # SDDM handles SIGTERM itself and returns 255 on a normal test shutdown.
        and stopped_by_test
        and process.returncode in (0, -15, 15, 255)
    )
    if failures or not loaded:
        raise SystemExit("FAIL: theme failed to load, exited early, or reported QML errors")
    print("PASS: theme loaded without fallback or QML reference/type errors")


if __name__ == "__main__":
    main()
