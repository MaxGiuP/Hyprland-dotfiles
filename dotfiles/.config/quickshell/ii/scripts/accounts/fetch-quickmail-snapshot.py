#!/usr/bin/env python3
"""Return a Quickshell-friendly QuickMail dashboard and agenda snapshot.

QuickMail remains the source of truth. This adapter only invokes its public
CLI and normalizes account/message/agenda metadata; it never requests message
bodies or credentials. Calendar reads intentionally use the same broad range
as QuickMail's calendar instead of the dashboard snapshot's short horizon.
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

AGENDA_SYNC_TIMEOUT_SECONDS = 120


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


def run_cli(binary, *arguments, timeout=10):
    result = subprocess.run(
        [str(binary), "--compact", *arguments],
        capture_output=True,
        check=False,
        text=True,
        timeout=timeout,
    )
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()
        raise RuntimeError(detail[-1] if detail else f"quickmailctl exited with code {result.returncode}")
    return json.loads(result.stdout)


def agenda_range_ms(now=None):
    """Match QuickMail's Jan(previous year) through Jan(+2 years) range."""
    anchor = now or dt.datetime.now()
    # Naive datetime.timestamp() applies the machine's real local timezone,
    # including the offset in January. datetime.now().astimezone().tzinfo can
    # be a fixed current offset and would be wrong across DST boundaries.
    start = dt.datetime(anchor.year - 1, 1, 1)
    end = dt.datetime(anchor.year + 2, 1, 1)
    return int(start.timestamp() * 1000), int(end.timestamp() * 1000)


def list_result(payload, key):
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict) and isinstance(payload.get(key), list):
        return payload[key]
    raise RuntimeError(f"QuickMail returned an invalid {key} response")


def agenda_sync_error(payload):
    if not isinstance(payload, dict) or not isinstance(payload.get("errors"), list):
        return ""
    for item in payload["errors"]:
        if isinstance(item, dict):
            message = str(first(item, "message", "error", "detail", default="") or "").strip()
        else:
            message = str(item or "").strip()
        if message:
            return f"QuickMail calendar: {message}"
    return ""


def load_quickmail_data(binary, request_sync=False, now=None):
    """Load dashboard metadata plus the authoritative task/calendar lists."""
    warnings = []
    agenda_sync = None
    if request_sync:
        try:
            agenda_sync = run_cli(
                binary,
                "agenda-sync",
                timeout=AGENDA_SYNC_TIMEOUT_SECONDS,
            )
            sync_warning = agenda_sync_error(agenda_sync)
            if sync_warning:
                warnings.append(sync_warning)
        except (OSError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
            warnings.append(f"QuickMail calendar synchronization failed: {error}")

    snapshot = run_cli(binary, "snapshot")
    if isinstance(snapshot, dict) and isinstance(snapshot.get("snapshot"), dict):
        snapshot = snapshot["snapshot"]
    if not isinstance(snapshot, dict):
        raise RuntimeError("QuickMail returned an invalid dashboard snapshot")
    snapshot = dict(snapshot)

    try:
        snapshot["tasks"] = list_result(
            run_cli(binary, "tasks", "--include-done"),
            "tasks",
        )
    except (OSError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        warnings.append(f"QuickMail tasks could not be refreshed: {error}")

    range_start, range_end = agenda_range_ms(now)
    try:
        snapshot["events"] = list_result(
            run_cli(
                binary,
                "events",
                "--start-at",
                str(range_start),
                "--end-at",
                str(range_end),
            ),
            "events",
        )
    except (OSError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        warnings.append(f"QuickMail events could not be refreshed: {error}")

    normalized = normalize(snapshot)
    if isinstance(agenda_sync, dict):
        normalized["agendaSync"] = agenda_sync
    existing_error = str(normalized.get("error", "") or "").strip()
    if existing_error:
        warnings.append(existing_error)
    normalized["error"] = "\n".join(dict.fromkeys(warnings))
    return normalized


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
        origin_source = str(first(raw, "source", default="") or "")
        provider = str(first(raw, "provider", default=account_providers.get(account_id, "QuickMail")))
        provider_default = provider_supports_tasks(provider) or provider_supports_tasks(origin_source)
        local_task = not account_id and origin_source.strip().lower() in ("", "local")
        writable = capability(
            raw,
            "writable",
            "taskWritable",
            "task_writable",
            default=account_task_writable.get(account_id, local_task or provider_default),
        )
        read_only = bool(first(raw, "readOnly", "read_only", default=not writable))
        writable = writable and not read_only
        date_only = bool(first(
            raw,
            "dateOnly",
            "date_only",
            "dueDateOnly",
            "due_date_only",
            default=account_task_date_only.get(
                account_id,
                provider_uses_date_only_tasks(provider) or provider_uses_date_only_tasks(origin_source),
            ),
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
            "originSource": origin_source,
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
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--sync", action="store_true")
    mode.add_argument("--watch", action="store_true")
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

    if args.watch:
        os.execv(
            str(binary),
            [str(binary), "--compact", "watch", "agenda"],
        )

    print(json.dumps(load_quickmail_data(binary, args.sync), ensure_ascii=False))


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
