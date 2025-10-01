#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse, os, re, sqlite3, sys, time, subprocess, json

TB_BASE = os.path.expanduser("~/.thunderbird")

def die(msg, code=1):
    print(msg, file=sys.stderr); sys.exit(code)

def now_utc_ics():
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())

def to_ms(val):
    try:
        v = int(val)
    except Exception:
        return None
    if v > 300_000_000_000_000:  # µs
        return v // 1000
    if v > 300_000_000_000:      # ms
        return v
    if v > 300_000_000:          # s
        return v * 1000
    return None

def fmt_ms(ms, all_day=False):
    if ms is None:
        return "(no date)" if all_day else "(no date)"
    try:
        import datetime as dt
        return dt.datetime.fromtimestamp(ms/1000).strftime("%d/%m/%Y" if all_day else "%d/%m/%Y %H:%M")
    except Exception:
        return "(bad date)"

# ---------- DB helpers ----------
def open_rw(db_path):
    if not os.path.isfile(db_path):
        die(f"[error] DB not found: {db_path}")
    try:
        con = sqlite3.connect(db_path)
        con.row_factory = sqlite3.Row
        return con
    except Exception as e:
        die(f"[error] cannot open db rw: {e}")

def cols(con, table):
    try:
        cur = con.execute(f"PRAGMA table_info({table});")
        return {r[1] for r in cur.fetchall()}
    except Exception:
        return set()

def pick(colset, candidates):
    for c in candidates:
        if c in colset:
            return c
    return None

def detect_profile_dir(profile):
    if profile:
        if os.path.isdir(profile): return profile
        p = os.path.join(TB_BASE, profile)
        if os.path.isdir(p): return p
    try:
        for name in os.listdir(TB_BASE):
            if name.endswith(".default-default"):
                p = os.path.join(TB_BASE, name)
                if os.path.isdir(p): return p
    except Exception:
        pass
    return None

def local_sqlite_from(profile_dir):
    p = os.path.join(profile_dir, "calendar-data", "local.sqlite")
    return p if os.path.isfile(p) else None

# ---------- ICS helpers (only used if ICS column exists) ----------
def unfold_ics(s):
    return (s or "").replace("\r", "").replace("\n ", "").replace("\n\t", "")

def fold_ics_line(line, limit=75):
    out = []
    while len(line.encode("utf-8")) > limit:
        cut = limit
        while len(line[:cut].encode("utf-8")) > limit:
            cut -= 1
        out.append(line[:cut])
        line = " " + line[cut:]
    out.append(line)
    return "\r\n".join(out)

def set_completed_in_vtodo(ics_text):
    txt = unfold_ics(ics_text)
    if "BEGIN:VTODO" not in txt:
        return ics_text
    lines = txt.split("\n")
    idx_status = idx_pct = idx_done = -1
    for i, L in enumerate(lines):
        U = L.upper()
        if U.startswith("STATUS:"): idx_status = i
        elif U.startswith("PERCENT-COMPLETE:"): idx_pct = i
        elif U.startswith("COMPLETED:"): idx_done = i
    if idx_status >= 0: lines[idx_status] = "STATUS:COMPLETED"
    else: lines.insert(len(lines)-1, "STATUS:COMPLETED")
    if idx_pct >= 0: lines[idx_pct] = "PERCENT-COMPLETE:100"
    else: lines.insert(len(lines)-1, "PERCENT-COMPLETE:100")
    stamp = f"COMPLETED:{now_utc_ics()}"
    if idx_done >= 0: lines[idx_done] = stamp
    else: lines.insert(len(lines)-1, stamp)
    refolded = [fold_ics_line(L) for L in lines]
    return "\r\n".join(refolded) + ("\r\n" if not refolded[-1].endswith("\r\n") else "")

def set_needs_action_in_vtodo(ics_text):
    txt = unfold_ics(ics_text)
    if "BEGIN:VTODO" not in txt:
        return ics_text
    lines = txt.split("\n")
    out = []
    saw_status = saw_pct = False
    for L in lines:
        U = L.upper()
        if U.startswith("STATUS:"): out.append("STATUS:NEEDS-ACTION"); saw_status = True
        elif U.startswith("PERCENT-COMPLETE:"): out.append("PERCENT-COMPLETE:0"); saw_pct = True
        elif U.startswith("COMPLETED:"): continue
        else: out.append(L)
    if not saw_status: out.insert(len(out)-1, "STATUS:NEEDS-ACTION")
    if not saw_pct:    out.insert(len(out)-1, "PERCENT-COMPLETE:0")
    refolded = [fold_ics_line(L) for L in out]
    return "\r\n".join(refolded) + ("\r\n" if not refolded[-1].endswith("\r\n") else "")

def extract_uid(ics_text):
    txt = unfold_ics(ics_text)
    m = re.search(r"^UID:(.+)$", txt, re.MULTILINE)
    return m.group(1).strip() if m else None

# ---------- TASKS ----------
def list_tasks(con):
    cset   = cols(con, "cal_todos")
    if not cset:
        die("[error] table cal_todos not found")

    icscol = pick(cset, ["icalString", "icalstring", "ical"])
    titlec = pick(cset, ["title", "summary"])
    duec   = pick(cset, ["todo_due", "todo_entry", "due", "due_ts"])
    statc  = pick(cset, ["status"])
    pctc   = pick(cset, ["percent_complete", "percent"])

    select_cols = ["rowid"]
    if icscol: select_cols.append(icscol)
    if titlec: select_cols.append(titlec)
    if duec:   select_cols.append(duec)
    if statc:  select_cols.append(statc)
    if pctc:   select_cols.append(pctc)

    sql = "SELECT " + ", ".join(select_cols) + " FROM cal_todos ORDER BY rowid ASC"
    rows = con.execute(sql).fetchall()

    out = []
    for r in rows:
        ics = r[icscol] if icscol else None
        out.append({
            "rowid":   r["rowid"],
            "uid":     (extract_uid(ics) if ics else "") or "",
            "title":   (r[titlec] if titlec else "") or "",
            "status":  (r[statc] if statc else "") or "",
            "percent": r[pctc] if pctc else None,
            "due_raw": r[duec] if duec else None,
            "_has_ics": bool(icscol)
        })
    return out

def pick_task_rowid_by_index(con, idx):
    rows = list_tasks(con)
    if idx < 0 or idx >= len(rows):
        die(f"[error] index out of range (0..{max(0, len(rows)-1)}): {idx}")
    return rows[idx]["rowid"], rows[idx]["_has_ics"]

def complete_task(con, *, rowid=None, uid=None):
    cset   = cols(con, "cal_todos")
    icscol = pick(cset, ["icalString", "icalstring", "ical"])
    statc  = pick(cset, ["status"])
    pctc   = pick(cset, ["percent_complete", "percent"])
    if rowid is None and uid is None:
        die("[error] need rowid or uid")

    if uid and not icscol:
        die("[error] this DB has no ICS column; complete by --complete-index or --complete <rowid>")

    where = "rowid=?" if rowid is not None else f"{icscol} LIKE ?"
    arg   = (rowid,) if rowid is not None else (f"%UID:{uid}%",)

    cur = con.execute(f"SELECT rowid{(','+icscol) if icscol else ''} FROM cal_todos WHERE {where} LIMIT 1", arg)
    row = cur.fetchone()
    if not row:
        die("[error] task not found]")

    sets, args = [], []
    if icscol:
        new_ics = set_completed_in_vtodo(row[icscol])
        sets.append(f"{icscol}=?"); args.append(new_ics)
    if statc:
        sets.append(f"{statc}=?"); args.append("COMPLETED")
    if pctc:
        sets.append(f"{pctc}=?");  args.append(100)

    if not sets:
        die("[error] no columns to update (no ICS and no status/percent columns)")

    args.append(row["rowid"])
    con.execute("BEGIN IMMEDIATE")
    con.execute(f"UPDATE cal_todos SET {', '.join(sets)} WHERE rowid=?", args)
    con.commit()
    return row["rowid"]

def uncomplete_task(con, *, rowid=None, uid=None):
    cset   = cols(con, "cal_todos")
    icscol = pick(cset, ["icalString", "icalstring", "ical"])
    statc  = pick(cset, ["status"])
    pctc   = pick(cset, ["percent_complete", "percent"])
    if rowid is None and uid is None:
        die("[error] need rowid or uid")

    if uid and not icscol:
        die("[error] this DB has no ICS column; uncomplete by --uncomplete-index or --uncomplete <rowid>")

    where = "rowid=?" if rowid is not None else f"{icscol} LIKE ?"
    arg   = (rowid,) if rowid is not None else (f"%UID:{uid}%",)

    cur = con.execute(f"SELECT rowid{(','+icscol) if icscol else ''} FROM cal_todos WHERE {where} LIMIT 1", arg)
    row = cur.fetchone()
    if not row:
        die("[error] task not found")

    sets, args = [], []
    if icscol:
        new_ics = set_needs_action_in_vtodo(row[icscol])
        sets.append(f"{icscol}=?"); args.append(new_ics)
    if statc:
        sets.append(f"{statc}=?"); args.append("NEEDS-ACTION")
    if pctc:
        sets.append(f"{pctc}=?");  args.append(0)

    if not sets:
        die("[error] no columns to update (no ICS and no status/percent columns)")

    args.append(row["rowid"])
    con.execute("BEGIN IMMEDIATE")
    con.execute(f"UPDATE cal_todos SET {', '.join(sets)} WHERE rowid=?", args)
    con.commit()
    return row["rowid"]

def delete_task(con, *, rowid=None, uid=None):
    cset   = cols(con, "cal_todos")
    icscol = pick(cset, ["icalString", "icalstring", "ical"])
    if rowid is None and uid is None:
        die("[error] need rowid or uid")
    if uid and not icscol:
        die("[error] this DB has no ICS column; delete by --delete-index or --delete <rowid>")

    where = "rowid=?" if rowid is not None else f"{icscol} LIKE ?"
    arg   = (rowid,) if rowid is not None else (f"%UID:{uid}%",)

    con.execute("BEGIN IMMEDIATE")
    cur = con.execute(f"DELETE FROM cal_todos WHERE {where}", arg)
    con.commit()
    return cur.rowcount

# ---------- EVENTS ----------
def list_events(con):
    cset = cols(con, "cal_events")
    if not cset:
        die("[error] table cal_events not found")

    icscol = pick(cset, ["icalString", "icalstring", "ical"])
    titlec = pick(cset, ["title", "summary"])
    startc = pick(cset, ["event_start", "dtstart", "occurrence_start", "start_ts", "start"])
    endc   = pick(cset, ["event_end",   "dtend",   "occurrence_end",   "end_ts",   "end"])
    tzcol  = pick(cset, ["event_start_tz", "start_tz", "timezone", "floating"])

    select_cols = ["rowid"]
    if icscol: select_cols.append(icscol)
    if titlec: select_cols.append(titlec)
    if startc: select_cols.append(startc)
    if endc:   select_cols.append(endc)
    if tzcol:  select_cols.append(tzcol)

    sql = "SELECT " + ", ".join(select_cols) + " FROM cal_events ORDER BY rowid ASC"
    rows = con.execute(sql).fetchall()

    out = []
    for r in rows:
        ics = r[icscol] if icscol else None
        # choose a time field to display
        raw = None
        if startc and r[startc] is not None: raw = r[startc]
        elif endc and r[endc] is not None:   raw = r[endc]
        ms = to_ms(raw)
        tz = (r[tzcol] if tzcol else "") or ""
        all_day = str(tz).lower() == "floating"
        out.append({
            "rowid":   r["rowid"],
            "uid":     (extract_uid(ics) if ics else "") or "",
            "title":   (r[titlec] if titlec else "") or "(No title)",
            "when_ms": ms,
            "when_str": fmt_ms(ms, all_day),
            "all_day": all_day,
            "_has_ics": bool(icscol)
        })
    return out

def pick_event_rowid_by_index(con, idx):
    rows = list_events(con)
    if idx < 0 or idx >= len(rows):
        die(f"[error] index out of range (0..{max(0, len(rows)-1)}): {idx}")
    return rows[idx]["rowid"], rows[idx]["_has_ics"]

def delete_event(con, *, rowid=None, uid=None):
    cset   = cols(con, "cal_events")
    icscol = pick(cset, ["icalString", "icalstring", "ical"])
    if rowid is None and uid is None:
        die("[error] need rowid or uid")
    if uid and not icscol:
        die("[error] this DB has no ICS column; delete by --delete-event-index or --delete-event <rowid>")

    where = "rowid=?" if rowid is not None else f"{icscol} LIKE ?"
    arg   = (rowid,) if rowid is not None else (f"%UID:{uid}%",)

    con.execute("BEGIN IMMEDIATE")
    cur = con.execute(f"DELETE FROM cal_events WHERE {where}", arg)
    con.commit()
    return cur.rowcount

# ---------- process state ----------
def betterbird_running():
    try:
        out = subprocess.run(["pidof","betterbird"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return out.returncode == 0 and out.stdout.strip() != b""
    except Exception:
        return False

# ---------- CLI ----------
def main():
    ap = argparse.ArgumentParser(description="Betterbird mutate: list/modify tasks and events")
    ap.add_argument("--profile", help="Profile dir (e.g., ~/.thunderbird/343n4iu7.default-default)")
    ap.add_argument("--db", help="Direct path to local.sqlite (overrides --profile)")

    # list
    ap.add_argument("--list",         action="store_true", help="List tasks (with 0-based index)")
    ap.add_argument("--list-events",  action="store_true", help="List events (with 0-based index)")
    ap.add_argument("--json",         action="store_true", help="JSON output for list modes")

    # task ops
    ap.add_argument("--complete",     metavar="UID_OR_ROWID", help="Complete task by UID or numeric rowid")
    ap.add_argument("--uncomplete",   metavar="UID_OR_ROWID", help="Uncomplete task by UID or numeric rowid")
    ap.add_argument("--delete",       metavar="UID_OR_ROWID", help="Delete task by UID or numeric rowid")
    ap.add_argument("--complete-index",   type=int, help="Complete task by index (0-based, rowid ASC)")
    ap.add_argument("--uncomplete-index", type=int, help="Uncomplete task by index (0-based, rowid ASC)")
    ap.add_argument("--delete-index",     type=int, help="Delete task by index (0-based, rowid ASC)")

    # event ops
    ap.add_argument("--delete-event",       metavar="UID_OR_ROWID", help="Delete event by UID or numeric rowid")
    ap.add_argument("--delete-event-index", type=int, help="Delete event by index (0-based, rowid ASC)")

    ap.add_argument("--force", action="store_true", help="Write even if Betterbird is running (risk of corruption)")
    args = ap.parse_args()

    if not args.db:
        prof = detect_profile_dir(args.profile)
        if not prof:
            die("[error] Could not determine profile. Use --db /path/to/local.sqlite or --profile DIR")
        db_path = local_sqlite_from(prof)
        if not db_path:
            die(f"[error] local.sqlite not found in {prof}/calendar-data")
    else:
        db_path = os.path.expanduser(args.db)

    # Safety: any write?
    writes = any([
        args.complete, args.uncomplete, args.delete,
        args.complete_index is not None, args.uncomplete_index is not None, args.delete_index is not None,
        args.delete_event, args.delete_event_index is not None
    ])
    if writes and (not args.force) and betterbird_running():
        die("[error] Betterbird appears to be running. Close it or pass --force (risk of corruption).")

    con = open_rw(db_path)

    # ----- LIST -----
    if args.list or args.list_events or (not writes and not args.list and not args.list_events):
        if args.list_events:
            rows = list_events(con)
            if args.json:
                print(json.dumps(rows, ensure_ascii=False, indent=2))
            else:
                if not rows:
                    print("(no events)")
                else:
                    for i, r in enumerate(rows):
                        print(f"[{i:>3}] rowid={r['rowid']}  UID={r['uid'] or '(no UID)'}  {r['when_str']}  {r['title']}")
        else:
            rows = list_tasks(con)
            if args.json:
                print(json.dumps(rows, ensure_ascii=False, indent=2))
            else:
                if not rows:
                    print("(no tasks)")
                else:
                    for i, r in enumerate(rows):
                        st  = r["status"] or "-"
                        pc  = r["percent"] if r["percent"] is not None else ""
                        print(f"[{i:>3}] rowid={r['rowid']}  UID={r['uid'] or '(no UID)'}  [{st} {pc if pc!='' else ''}]  {r['title'] or '(No title)'}")
        return

    # ----- TASK index-based -----
    if args.complete_index is not None:
        rid, _ = pick_task_rowid_by_index(con, int(args.complete_index))
        rid = complete_task(con, rowid=rid); print(f"[ok] marked completed: rowid={rid}"); return

    if args.uncomplete_index is not None:
        rid, _ = pick_task_rowid_by_index(con, int(args.uncomplete_index))
        rid = uncomplete_task(con, rowid=rid); print(f"[ok] marked uncompleted: rowid={rid}"); return

    if args.delete_index is not None:
        rid, _ = pick_task_rowid_by_index(con, int(args.delete_index))
        n = delete_task(con, rowid=rid); print(f"[ok] deleted rows: {n} (rowid={rid})"); return

    # ----- EVENT index-based -----
    if args.delete_event_index is not None:
        rid, _ = pick_event_rowid_by_index(con, int(args.delete_event_index))
        n = delete_event(con, rowid=rid); print(f"[ok] deleted event rows: {n} (rowid={rid})"); return

    # ----- UID/rowid direct -----
    # Tasks
    if args.complete:
        rowid = int(args.complete, 10) if args.complete.isdigit() else None
        uid   = None if rowid is not None else args.complete
        rid = complete_task(con, rowid=rowid, uid=uid)
        print(f"[ok] marked completed: rowid={rid}")
        return

    if args.uncomplete:
        rowid = int(args.uncomplete, 10) if args.uncomplete.isdigit() else None
        uid   = None if rowid is not None else args.uncomplete
        rid = uncomplete_task(con, rowid=rowid, uid=uid)
        print(f"[ok] marked uncompleted: rowid={rid}")
        return

    if args.delete:
        rowid = int(args.delete, 10) if args.delete.isdigit() else None
        uid   = None if rowid is not None else args.delete
        n = delete_task(con, rowid=rowid, uid=uid)
        print(f"[ok] deleted rows: {n}")
        return

    # Events
    if args.delete_event:
        rowid = int(args.delete_event, 10) if args.delete_event.isdigit() else None
        uid   = None if rowid is not None else args.delete_event
        n = delete_event(con, rowid=rowid, uid=uid)
        print(f"[ok] deleted event rows: {n}")
        return

if __name__ == "__main__":
    main()
