#!/usr/bin/env python3
"""Forward workspace events from Hyprland, reconnecting without process churn."""

import math
import os
import socket
import sys
import time


EVENT_PREFIXES = (b"workspace>>", b"workspacev2>>", b"focusedmon>>")
INITIAL_BACKOFF_SECONDS = 0.25
MAX_BACKOFF_SECONDS = 15.0
CONNECT_TIMEOUT_SECONDS = 5.0
STABLE_CONNECTION_SECONDS = 5.0
MAX_EVENT_BYTES = 64 * 1024


class OutputClosedError(Exception):
    """Raised when the parent process no longer consumes forwarded events."""


def configured_seconds(name: str, default: float, minimum: float, maximum: float) -> float:
    """Read a finite, bounded duration from the environment."""
    try:
        value = float(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default
    if not math.isfinite(value) or not minimum <= value <= maximum:
        return default
    return value


def forward_connection(socket_path: str, connect_timeout: float) -> float:
    """Forward one connection and return how long it remained connected."""
    connected_at = time.monotonic()

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(connect_timeout)
        connection.connect(socket_path)
        connection.settimeout(None)
        connected_at = time.monotonic()

        with connection.makefile("rb") as stream:
            while True:
                line = stream.readline(MAX_EVENT_BYTES + 1)
                if not line:
                    break
                if len(line) > MAX_EVENT_BYTES:
                    while line and not line.endswith(b"\n"):
                        line = stream.readline(MAX_EVENT_BYTES + 1)
                    continue
                # A compositor restart can cut the final record in half. Never
                # join that fragment to the first event on the next connection.
                if not line.endswith(b"\n"):
                    continue
                if not line.startswith(EVENT_PREFIXES):
                    continue
                try:
                    sys.stdout.buffer.write(line)
                    sys.stdout.buffer.flush()
                except (OSError, ValueError):
                    raise OutputClosedError from None

    return time.monotonic() - connected_at


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} SOCKET", file=sys.stderr)
        return 2

    initial_backoff = configured_seconds(
        "QS_WORKSPACE_EVENT_INITIAL_BACKOFF", INITIAL_BACKOFF_SECONDS, 0.05, 5.0
    )
    max_backoff = configured_seconds(
        "QS_WORKSPACE_EVENT_MAX_BACKOFF", MAX_BACKOFF_SECONDS, initial_backoff, 60.0
    )
    connect_timeout = configured_seconds(
        "QS_WORKSPACE_EVENT_CONNECT_TIMEOUT", CONNECT_TIMEOUT_SECONDS, 0.1, 30.0
    )
    backoff = initial_backoff

    while True:
        connection_age = 0.0
        try:
            connection_age = forward_connection(sys.argv[1], connect_timeout)
        except OutputClosedError:
            return 0
        except OSError:
            # Socket absence, compositor restarts, and peer resets are expected.
            # Keep these quiet so a temporary outage cannot flood the journal.
            pass
        except KeyboardInterrupt:
            return 0

        stable_connection = connection_age >= STABLE_CONNECTION_SECONDS
        if stable_connection:
            backoff = initial_backoff

        try:
            time.sleep(backoff)
        except KeyboardInterrupt:
            return 0

        if not stable_connection:
            backoff = min(max_backoff, backoff * 2)


if __name__ == "__main__":
    raise SystemExit(main())
