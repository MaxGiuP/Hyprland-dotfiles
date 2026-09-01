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


WRITABLE_TASK_PROVIDERS = {
    "gmail",
    "google",
    "outlook",
    "hotmail",
    "microsoft",
    "microsoft365",
    "office365",
}


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


def provider_supports_tasks(provider):
    return str(provider or "").strip().lower() in WRITABLE_TASK_PROVIDERS


def provider_uses_date_only_tasks(provider):
    normalized = str(provider or "").strip().lower()
    return "gmail" in normalized or "google" in normalized


def capability(mapping, *keys, default=False):
    capabilities = first(mapping, "capabilities", default={}) or {}
    explicit = first(mapping, *keys, default=None)
    if explicit is None and isinstance(capabilities, dict):
        explicit = first(capabilities, *keys, default=None)
    return bool(default if explicit is None else explicit)


def derive_event_account_id(calendar_id, calendar_name, accounts):
    """Recover an event's account when older snapshots omit accountId."""
    calendar_id_folded = str(calendar_id or "").strip().casefold()
    calendar_name_folded = str(calendar_name or "").strip().casefold()
    for account in accounts:
        account_id = str(account.get("id", "")).strip()
        if not account_id:
            continue
        account_id_folded = account_id.casefold()
        names = {
            account_id_folded,
            str(account.get("address", "")).strip().casefold(),
            str(account.get("displayName", "")).strip().casefold(),
        }
        names.discard("")
        if calendar_id_folded in names or calendar_name_folded in names:
            return account_id
        if any(
            calendar_id_folded.startswith(f"{account_id_folded}{separator}")
            or calendar_id_folded.endswith(f"{separator}{account_id_folded}")
            for separator in (":", "/", "|", "#")
        ):
            return account_id
    if len(accounts) == 1:
        return str(accounts[0].get("id", ""))
    return ""


def normalize(snapshot):
    if isinstance(snapshot.get("snapshot"), dict):
        snapshot = snapshot["snapshot"]

    raw_accounts = first(snapshot, "accounts", default=[]) or []
    accounts = []
    account_addresses = {}
    account_providers = {}
    account_task_writable = {}
    account_task_date_only = {}
    for raw in raw_accounts:
        account_id = str(first(raw, "id", "accountId", "account_id", default=""))
        address = str(first(raw, "address", "email", default=""))
        provider = str(first(raw, "provider", default="QuickMail"))
        task_writable = capability(
            raw,
            "taskWritable",
            "task_writable",
            "tasksWrite",
            "tasks_write",
            default=provider_supports_tasks(provider),
        )
        task_date_only = capability(
            raw,
            "taskDateOnly",
            "task_date_only",
            "taskDueDateOnly",
            "task_due_date_only",
            default=provider_uses_date_only_tasks(provider),
        )
        account_addresses[account_id] = address
        account_providers[account_id] = provider
        account_task_writable[account_id] = task_writable
        account_task_date_only[account_id] = task_date_only
        accounts.append({
            "id": account_id,
            "address": address,
            "displayName": str(first(raw, "displayName", "display_name", default="")),
            "host": str(first(raw, "host", default="")),
            "provider": provider,
            "protocol": str(first(raw, "protocol", default="")),
            "unread": int(first(raw, "unread", "unreadCount", "unread_count", default=0) or 0),
            "total": int(first(raw, "total", "messageCount", "message_count", default=0) or 0),
            "taskWritable": task_writable,
            "taskDateOnly": task_date_only,
            "calendarWritable": capability(
                raw,
                "calendarWritable",
                "calendar_writable",
                "calendarWrite",
                "calendar_write",
                default=False,
            ),
            "capabilities": first(raw, "capabilities", default={}) or {},
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
        account_id = str(first(raw, "accountId", "account_id", "account", default=""))
        provider = str(first(raw, "provider", default=account_providers.get(account_id, "QuickMail")))
        writable = capability(
            raw,
            "writable",
            "taskWritable",
            "task_writable",
            default=account_task_writable.get(account_id, provider_supports_tasks(provider)),
        )
        read_only = bool(first(raw, "readOnly", "read_only", default=not writable))
        writable = writable and not read_only
        date_only = bool(first(
            raw,
            "dateOnly",
            "date_only",
            "dueDateOnly",
            "due_date_only",
            default=account_task_date_only.get(account_id, provider_uses_date_only_tasks(provider)),
        ))
        tasks.append({
            "id": str(first(raw, "id", default="")),
            "externalId": str(first(raw, "externalId", "external_id", "id", default="")),
            "content": str(first(raw, "title", "content", default="")),
            "title": str(first(raw, "title", "content", default="")),
            "description": str(first(raw, "description", default="")),
            "done": bool(first(raw, "done", "completed", default=False)),
            "dueAt": timestamp_ms(first(raw, "dueAt", "due_at", default=0)),
            "entryAt": timestamp_ms(first(raw, "createdAt", "created_at", default=0)),
            "accountId": account_id,
            "account": account_addresses.get(account_id, account_id),
            "provider": provider,
            "calendarName": str(first(
                raw,
                "calendarName",
                "calendar_name",
                default=account_addresses.get(account_id, account_id) or "QuickMail",
            )),
            "taskListId": str(first(raw, "taskListId", "task_list_id", default="")),
            "source": "quickmail-task",
            "writable": writable,
            "readOnly": read_only,
            "dateOnly": date_only,
            "capabilities": first(raw, "capabilities", default={}) or {},
        })

    events = []
    for raw in first(snapshot, "events", default=[]) or []:
        calendar_id = str(first(raw, "calendarId", "calendar_id", default=""))
        calendar_name = str(first(raw, "calendarName", "calendar_name", default="QuickMail"))
        account_id = str(first(raw, "accountId", "account_id", "account", default=""))
        if not account_id:
            account_id = derive_event_account_id(calendar_id, calendar_name, accounts)
        provider = str(first(raw, "provider", default=account_providers.get(account_id, "QuickMail")))
        read_only = bool(first(raw, "readOnly", "read_only", default=True))
        writable = capability(raw, "writable", "calendarWritable", "calendar_writable", default=not read_only) and not read_only
        events.append({
            "id": str(first(raw, "id", default="")),
            "externalId": str(first(raw, "externalId", "external_id", "id", default="")),
            "calId": calendar_id,
            "accountId": account_id,
            "account": account_addresses.get(account_id, account_id),
            "provider": provider,
            "calendarName": calendar_name,
            "title": str(first(raw, "title", default="")),
            "description": str(first(raw, "description", default="")),
            "startAt": timestamp_ms(first(raw, "startAt", "start_at", default=0)),
            "endAt": timestamp_ms(first(raw, "endAt", "end_at", default=0)),
            "allDay": bool(first(raw, "allDay", "all_day", default=False)),
            "writable": writable,
            "readOnly": read_only,
            "capabilities": first(raw, "capabilities", default={}) or {},
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
