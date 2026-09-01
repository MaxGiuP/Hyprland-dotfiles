#!/usr/bin/env python3
"""Return a Quickshell-friendly QuickMail dashboard snapshot.

QuickMail remains the source of truth. This adapter only invokes its public
CLI and normalizes account/message/agenda metadata; it never requests message
bodies or credentials.
"""

import argparse
import datetime as dt
import json
import os
import shutil
import subprocess
from pathlib import Path


def quickmailctl_path():
    override = os.environ.get("QUICKMAILCTL", "").strip()
    candidates = [
        Path(override) if override else None,
        Path(shutil.which("quickmailctl")) if shutil.which("quickmailctl") else None,
        Path.home() / "QuickMail/target/release/quickmailctl",
        Path.home() / "QuickMail/target/debug/quickmailctl",
    ]
    return next((path for path in candidates if path and path.is_file() and os.access(path, os.X_OK)), None)


def first(mapping, *keys, default=None):
    for key in keys:
        if key in mapping and mapping[key] is not None:
            return mapping[key]
    return default


def timestamp_ms(value):
    if value in (None, ""):
        return 0
    if isinstance(value, (int, float)):
        number = int(value)
        if number < 10_000_000_000:
            return number * 1000
        if number > 10_000_000_000_000:
            return number // 1000
        return number
    try:
        parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return int(parsed.timestamp() * 1000)
    except ValueError:
        return 0


def run_cli(binary, *arguments):
    result = subprocess.run(
        [str(binary), "--compact", *arguments],
        capture_output=True,
        check=False,
        text=True,
        timeout=10,
    )
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()
        raise RuntimeError(detail[-1] if detail else f"quickmailctl exited with code {result.returncode}")
    return json.loads(result.stdout)


def author_text(author):
    if isinstance(author, dict):
        name = str(first(author, "name", "displayName", default="")).strip()
        address = str(first(author, "address", "email", default="")).strip()
        return name or address
    return str(author or "").strip()


def normalize(snapshot):
    if isinstance(snapshot.get("snapshot"), dict):
        snapshot = snapshot["snapshot"]

    raw_accounts = first(snapshot, "accounts", default=[]) or []
    accounts = []
    account_addresses = {}
    for raw in raw_accounts:
        account_id = str(first(raw, "id", "accountId", "account_id", default=""))
        address = str(first(raw, "address", "email", default=""))
        account_addresses[account_id] = address
        accounts.append({
            "id": account_id,
            "address": address,
            "displayName": str(first(raw, "displayName", "display_name", default="")),
            "host": str(first(raw, "host", default="")),
            "provider": str(first(raw, "provider", default="QuickMail")),
            "protocol": str(first(raw, "protocol", default="")),
            "unread": int(first(raw, "unread", "unreadCount", "unread_count", default=0) or 0),
            "total": int(first(raw, "total", "messageCount", "message_count", default=0) or 0),
        })

    raw_messages = first(snapshot, "recentMail", "recent_mail", "messages", default=[]) or []
    messages = []
    for raw in raw_messages:
        account_id = str(first(raw, "accountId", "account_id", default=""))
        messages.append({
            "id": str(first(raw, "id", "messageId", "message_id", default="")),
            "title": str(first(raw, "subject", "title", default="(No subject)")),
            "author": author_text(first(raw, "author", "from", default="")),
            "timestamp": timestamp_ms(first(raw, "timestamp", "date", default=0)),
            "read": bool(first(raw, "read", "isRead", "is_read", default=False)),
            "starred": bool(first(raw, "starred", "isStarred", "is_starred", default=False)),
            "account": account_addresses.get(account_id, account_id),
            "accountId": account_id,
            "provider": str(first(raw, "provider", default="QuickMail")),
        })

    tasks = []
    for raw in first(snapshot, "tasks", default=[]) or []:
        tasks.append({
            "id": str(first(raw, "id", default="")),
            "externalId": str(first(raw, "externalId", "external_id", "id", default="")),
            "content": str(first(raw, "title", "content", default="")),
            "title": str(first(raw, "title", "content", default="")),
            "description": str(first(raw, "description", default="")),
            "done": bool(first(raw, "done", "completed", default=False)),
            "dueAt": timestamp_ms(first(raw, "dueAt", "due_at", default=0)),
            "entryAt": timestamp_ms(first(raw, "createdAt", "created_at", default=0)),
            "calendarName": str(first(raw, "account", "calendarName", "calendar_name", default="QuickMail")),
            "source": "quickmail-task",
            "readOnly": True,
        })

    events = []
    for raw in first(snapshot, "events", default=[]) or []:
        calendar_id = str(first(raw, "calendarId", "calendar_id", default=""))
        events.append({
            "id": str(first(raw, "id", default="")),
            "externalId": str(first(raw, "externalId", "external_id", "id", default="")),
            "calId": calendar_id,
            "calendarName": str(first(raw, "calendarName", "calendar_name", default="QuickMail")),
            "title": str(first(raw, "title", default="")),
            "description": str(first(raw, "description", default="")),
            "startAt": timestamp_ms(first(raw, "startAt", "start_at", default=0)),
            "endAt": timestamp_ms(first(raw, "endAt", "end_at", default=0)),
            "allDay": bool(first(raw, "allDay", "all_day", default=False)),
            "readOnly": bool(first(raw, "readOnly", "read_only", default=True)),
            "source": "quickmail-event",
        })

    sync = first(snapshot, "sync", default={}) or {}
    return {
        "available": True,
        "revision": int(first(snapshot, "revision", default=0) or 0),
        "accounts": accounts,
        "messages": messages,
        "tasks": tasks,
        "events": events,
        "sync": sync,
        "error": str(first(sync, "error", default="") or ""),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sync", action="store_true")
    args = parser.parse_args()
    binary = quickmailctl_path()
    if binary is None:
        print(json.dumps({
            "available": False,
            "accounts": [],
            "messages": [],
            "tasks": [],
            "events": [],
            "sync": {},
            "error": "QuickMail is still being built; quickmailctl is not available yet.",
        }))
        return

    if args.sync:
        try:
            run_cli(binary, "sync")
        except (OSError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError):
            pass
    snapshot = run_cli(binary, "snapshot")
    print(json.dumps(normalize(snapshot), ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        print(json.dumps({
            "available": False,
            "accounts": [],
            "messages": [],
            "tasks": [],
            "events": [],
            "sync": {},
            "error": f"QuickMail service unavailable: {error}",
        }))
