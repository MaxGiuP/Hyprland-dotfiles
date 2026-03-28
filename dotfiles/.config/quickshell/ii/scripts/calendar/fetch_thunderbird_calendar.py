#!/usr/bin/env python3
import json
import os
import shutil
import sqlite3
import tempfile
from pathlib import Path


def normalize_ts_to_ms(value):
    if value is None:
        return 0
    try:
        ts = int(value)
    except (TypeError, ValueError):
        return 0
    if ts <= 0:
        return 0
    # Thunderbird calendar DB uses microseconds in most installs.
    if ts > 10_000_000_000_000:
        return ts // 1000
    # Already milliseconds
    if ts > 10_000_000_000:
        return ts
    # Seconds fallback
    return ts * 1000


def pick_profile():
    roots = [Path.home() / ".thunderbird"]
    for home_dir in Path("/home").glob("*"):
        roots.append(home_dir / ".thunderbird")

    candidates = []
    for tb_root in roots:
        if not tb_root.exists():
            continue
        for profile in tb_root.iterdir():
            if not profile.is_dir():
                continue
            cal_dir = profile / "calendar-data"
            cache_db = cal_dir / "cache.sqlite"
            local_db = cal_dir / "local.sqlite"
            if cache_db.exists() or local_db.exists():
                try:
                    mtime = max(
                        cache_db.stat().st_mtime if cache_db.exists() else 0,
                        local_db.stat().st_mtime if local_db.exists() else 0,
                    )
                except OSError:
                    mtime = 0
                candidates.append((mtime, profile))

    if not candidates:
        return None

    candidates.sort(key=lambda x: x[0], reverse=True)
    return candidates[0][1]


def copy_db(src):
    if not src.exists():
        return None
    tmp_dir = tempfile.mkdtemp(prefix="tb-cal-")
    dst = Path(tmp_dir) / src.name
    shutil.copy2(src, dst)
    return dst


def fetch_rows(db_path, query):
    try:
        conn = sqlite3.connect(str(db_path))
        cur = conn.cursor()
        cur.execute(query)
        rows = cur.fetchall()
        conn.close()
        return rows
    except sqlite3.Error:
        return []


def read_db(db_path):
    if not db_path or not Path(db_path).exists():
        return [], []

    todo_query = (
        "SELECT cal_id, id, title, todo_entry, todo_due, todo_completed, "
        "todo_complete, ical_status, last_modified FROM cal_todos"
    )
    event_query = (
        "SELECT cal_id, id, title, event_start, event_end, "
        "event_start_tz, event_end_tz, last_modified FROM cal_events"
    )

    todos = []
    for row in fetch_rows(db_path, todo_query):
        cal_id, item_id, title, entry, due, completed_at, complete_pct, status, modified = row
        title = (title or "").strip()
        if not title:
            continue
        done = False
        try:
            done = int(complete_pct or 0) >= 100 or (status or "").upper() in ("COMPLETED", "CANCELLED")
        except (ValueError, TypeError):
            done = (status or "").upper() in ("COMPLETED", "CANCELLED")

        todos.append(
            {
                "source": "thunderbird",
                "calId": cal_id,
                "externalId": item_id,
                "content": title,
                "done": done,
                "entryAt": normalize_ts_to_ms(entry),
                "dueAt": normalize_ts_to_ms(due),
                "completedAt": normalize_ts_to_ms(completed_at),
                "status": status or "",
                "lastModified": normalize_ts_to_ms(modified),
            }
        )

    events = []
    for row in fetch_rows(db_path, event_query):
        cal_id, item_id, title, start, end, start_tz, end_tz, modified = row
        title = (title or "").strip()
        if not title:
            continue
        start_ms = normalize_ts_to_ms(start)
        end_ms = normalize_ts_to_ms(end)
        events.append(
            {
                "source": "thunderbird",
                "calId": cal_id,
                "externalId": item_id,
                "title": title,
                "startAt": start_ms,
                "endAt": end_ms,
                "allDay": ((end_ms - start_ms) % 86400000 == 0) and (start_ms > 0 and end_ms > 0),
                "startTz": start_tz or "",
                "endTz": end_tz or "",
                "lastModified": normalize_ts_to_ms(modified),
            }
        )

    return todos, events


def dedupe(items, key_fields):
    by_key = {}
    for item in items:
        key = tuple(item.get(field, "") for field in key_fields)
        prev = by_key.get(key)
        if not prev or item.get("lastModified", 0) >= prev.get("lastModified", 0):
            by_key[key] = item
    return list(by_key.values())


def main():
    profile = pick_profile()
    if not profile:
        print(json.dumps({"profile": "", "tasks": [], "events": [], "error": "No Thunderbird profile with calendar-data found"}))
        return

    cal_dir = profile / "calendar-data"
    local_db = copy_db(cal_dir / "local.sqlite")
    cache_db = copy_db(cal_dir / "cache.sqlite")

    all_tasks = []
    all_events = []

    for db in [local_db, cache_db]:
        if not db:
            continue
        tasks, events = read_db(db)
        all_tasks.extend(tasks)
        all_events.extend(events)

    all_tasks = dedupe(all_tasks, ["externalId", "calId"])
    all_events = dedupe(all_events, ["externalId", "calId"])

    all_tasks.sort(key=lambda x: (x.get("dueAt", 0) or 0, x.get("content", "").lower()))
    all_events.sort(key=lambda x: (x.get("startAt", 0) or 0, x.get("title", "").lower()))

    print(
        json.dumps(
            {
                "profile": str(profile),
                "tasks": all_tasks,
                "events": all_events,
                "error": "",
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
