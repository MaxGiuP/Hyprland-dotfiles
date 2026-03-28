#!/usr/bin/env python3
import configparser
import json
import os
import shutil
import sqlite3
import tempfile
from pathlib import Path


TB_BASE = Path.home() / ".thunderbird"
PROFILES_INI = TB_BASE / "profiles.ini"


def normalize_ts_to_ms(value):
    if value is None:
        return 0
    try:
        ts = int(value)
    except (TypeError, ValueError):
        return 0
    if ts <= 0:
        return 0
    if ts > 10_000_000_000_000:
        return ts // 1000
    if ts > 10_000_000_000:
        return ts
    return ts * 1000


def resolve_profile_path(base_dir, path_value, is_relative):
    if not path_value:
        return None
    if is_relative:
        return base_dir / path_value
    return Path(os.path.expanduser(path_value))


def discover_profiles():
    profiles = []
    seen = set()

    if PROFILES_INI.exists():
        parser = configparser.RawConfigParser()
        parser.read(PROFILES_INI)
        for section in parser.sections():
            if not section.startswith("Profile"):
                continue
            path_value = parser.get(section, "Path", fallback="")
            is_relative = parser.get(section, "IsRelative", fallback="1") == "1"
            profile_dir = resolve_profile_path(TB_BASE, path_value, is_relative)
            if profile_dir and profile_dir.is_dir() and profile_dir not in seen:
                profiles.append(profile_dir)
                seen.add(profile_dir)

    if TB_BASE.exists():
        for profile_dir in sorted(TB_BASE.iterdir()):
            if profile_dir.is_dir() and (profile_dir / "calendar-data").is_dir() and profile_dir not in seen:
                profiles.append(profile_dir)
                seen.add(profile_dir)

    return profiles


def discover_calendar_dbs():
    dbs = []
    for profile_dir in discover_profiles():
        cal_dir = profile_dir / "calendar-data"
        for name in ("local.sqlite", "cache.sqlite"):
            db_path = cal_dir / name
            if db_path.exists():
                dbs.append((profile_dir, db_path))
    return dbs


def copy_db(src):
    if not src.exists():
        return None, None
    tmp_dir = tempfile.mkdtemp(prefix="tb-cal-")
    dst = Path(tmp_dir) / src.name
    shutil.copy2(src, dst)
    for suffix in ("-wal", "-shm"):
        aux = Path(f"{src}{suffix}")
        if aux.exists():
            shutil.copy2(aux, Path(f"{dst}{suffix}"))
    return dst, Path(tmp_dir)


def fetch_rows(db_path, query):
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro&immutable=1", uri=True)
        cur = conn.cursor()
        cur.execute(query)
        rows = cur.fetchall()
        conn.close()
        return rows
    except sqlite3.Error:
        return []


def read_db(profile_dir, db_path):
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
        try:
            done = int(complete_pct or 0) >= 100 or (status or "").upper() in ("COMPLETED", "CANCELLED")
        except (ValueError, TypeError):
            done = (status or "").upper() in ("COMPLETED", "CANCELLED")

        todos.append(
            {
                "source": "thunderbird",
                "profile": str(profile_dir),
                "dbPath": str(db_path),
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
                "profile": str(profile_dir),
                "dbPath": str(db_path),
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
    dbs = discover_calendar_dbs()
    if not dbs:
        print(json.dumps({"profile": "", "profiles": [], "tasks": [], "events": [], "error": "No Thunderbird calendar databases found"}))
        return

    all_tasks = []
    all_events = []
    profiles = []

    for profile_dir, src_db in dbs:
        copied_db, tmp_dir = copy_db(src_db)
        if copied_db is None:
            continue
        profiles.append(str(profile_dir))
        try:
            tasks, events = read_db(profile_dir, copied_db)
            all_tasks.extend(tasks)
            all_events.extend(events)
        finally:
            try:
                shutil.rmtree(tmp_dir)
            except OSError:
                pass

    all_tasks = dedupe(all_tasks, ["profile", "externalId", "calId"])
    all_events = dedupe(all_events, ["profile", "externalId", "calId", "startAt"])

    all_tasks.sort(key=lambda x: (x.get("dueAt", 0) or x.get("entryAt", 0) or 0, x.get("content", "").lower()))
    all_events.sort(key=lambda x: (x.get("startAt", 0) or 0, x.get("title", "").lower()))

    print(
        json.dumps(
            {
                "profile": profiles[0] if profiles else "",
                "profiles": profiles,
                "tasks": all_tasks,
                "events": all_events,
                "error": "",
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
