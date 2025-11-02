#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os, sys, sqlite3, shutil, tempfile, time, re, json, argparse

DB_DIR  = "/home/linmax/.thunderbird/343n4iu7.default-default/calendar-data"
DB_PATH = os.path.join(DB_DIR, "local.sqlite")
ROW_LIMIT_DEFAULT = 1000

def log(s): print(s, flush=True)

# -------- helpers --------
def to_ms(v):
    try: n = int(v)
    except Exception: return None
    if n > 300_000_000_000_000: return n // 1000
    if n > 300_000_000_000:     return n
    if n > 300_000_000:         return n * 1000
    return None

def fmt_ms(ms, all_day=False):
    if ms is None: return "(no date)"
    import datetime as dt
    try:
        return dt.datetime.fromtimestamp(ms/1000).strftime("%d/%m/%Y" if all_day else "%d/%m/%Y %H:%M")
    except Exception:
        return "(bad date)"

def ics_unfold(s): return (s or "").replace("\r","").replace("\n ","").replace("\n\t","")
def ics_get_first(txt, key):
    for line in txt.split("\n"):
        if line.startswith(key + ":") or line.startswith(key + ";"): return line
    return ""
def ics_val(line):
    i = line.find(":"); 
    return line[i+1:].strip() if i >= 0 else ""
def parse_ics_date(val):
    if not val: return None
    m = re.match(r"^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$", val)
    if not m: return None
    y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
    import datetime as dt, calendar
    if m.group(4):
        hh, mi, ss = int(m.group(4)), int(m.group(5)), int(m.group(6))
        if m.group(7) == "Z":
            return calendar.timegm(dt.datetime(y,mo,d,hh,mi,ss).timetuple()) * 1000
        return int(dt.datetime(y,mo,d,hh,mi,ss).timestamp() * 1000)
    return int(dt.datetime(y,mo,d).timestamp() * 1000)

# -------- snapshot + open --------
def snapshot_db(src):
    tmpdir = tempfile.mkdtemp(prefix="bb_local_")
    dst = os.path.join(tmpdir, "local.sqlite")
    t0 = time.time()
    shutil.copy2(src, dst)
    for suf in ("-wal","-shm"):
        aux = src + suf
        if os.path.isfile(aux):
            shutil.copy2(aux, dst + suf)
    log(f"[snapshot] {src} -> {dst} ({os.path.getsize(dst)} bytes) in {time.time()-t0:.3f}s")
    return dst, tmpdir

def open_immutable(path):
    return sqlite3.connect(f"file:{path}?mode=ro&immutable=1", uri=True)

# -------- schema helpers --------
def list_tables(con):
    try:
        cur = con.execute("SELECT name FROM sqlite_master WHERE type='table'")
        return [r[0] for r in cur.fetchall()]
    except Exception:
        return []

def table_cols(con, tname):
    try:
        cur = con.execute(f"PRAGMA table_info({tname})")
        return [r[1] for r in cur.fetchall()]
    except Exception:
        return []

def pick(cols, cand):
    for c in cand:
        if c in cols: return c
    return None

# -------- queries (no empty COALESCE) --------
def fetch_events(con, src_label, limit_rows):
    tables = list_tables(con)
    evt_tbl = "cal_events" if "cal_events" in tables else next((t for t in tables if "event" in t.lower()), None)
    if not evt_tbl: return []

    cols = table_cols(con, evt_tbl)
    title = pick(cols, ["title","summary","event_title"])
    start = pick(cols, ["event_start","dtstart","occurrence_start","start_ts","start"])
    end   = pick(cols, ["event_end","dtend","occurrence_end","end_ts","end"])
    tz    = pick(cols, ["event_start_tz","start_tz","timezone","floating"])
    ics   = pick(cols, ["icalString","icalstring","ical"])

    out = []
    if (title or ics) and (start or end or ics):
        title_expr = f"COALESCE({title},'(No title)')" if title else "'(No title)'"
        time_expr  = f"CAST({(start or end)} AS INTEGER)" if (start or end) else "NULL"
        tz_expr    = tz or "''"
        order_expr = (start or end or "1")
        sql = f"""SELECT {title_expr}, {time_expr}, {tz_expr}
                  FROM {evt_tbl}
                  ORDER BY {order_expr} ASC
                  LIMIT {int(limit_rows)}"""
        try:
            for title_v, ts_any, tzv in con.execute(sql):
                out.append({
                    "title": title_v or "(No title)",
                    "whenMs": to_ms(ts_any),
                    "allDay": (str(tzv).lower()=="floating"),
                    "src": src_label
                })
        except Exception:
            pass
    if not out and ics:
        try:
            for (ical,) in con.execute(f"SELECT {ics} FROM {evt_tbl} LIMIT {int(limit_rows)}"):
                txt = ics_unfold(ical or "")
                if "BEGIN:VEVENT" not in txt: continue
                ttl = ics_val(ics_get_first(txt,"SUMMARY")) or "(No title)"
                when = parse_ics_date(ics_val(ics_get_first(txt,"DTSTART"))) or parse_ics_date(ics_get_first(txt,"DTEND"))
                out.append({"title": ttl, "whenMs": when, "allDay": False, "src": src_label})
        except Exception:
            pass
    return out

def fetch_tasks(con, src_label, limit_rows):
    tables = list_tables(con)
    todo_tbl = "cal_todos" if "cal_todos" in tables else next((t for t in tables if "todo" in t.lower()), None)
    if not todo_tbl: return []

    cols = table_cols(con, todo_tbl)
    title = pick(cols, ["title","summary"])
    due   = pick(cols, ["todo_due","todo_entry","due","due_ts"])
    stat  = pick(cols, ["status"])
    pct   = pick(cols, ["percent_complete","percent"])
    ics   = pick(cols, ["icalString","icalstring","ical"])

    title_expr = f"COALESCE({title},'(No title)')" if title else "'(No title)'"
    due_expr   = f"CAST({due} AS INTEGER)" if due else "NULL"
    stat_expr  = stat if stat else "''"
    pct_expr   = pct  if pct  else "0"
    ics_expr   = ics  if ics  else "''"

    sql = f"""SELECT {title_expr}, {due_expr}, {stat_expr}, {pct_expr}, {ics_expr}
              FROM {todo_tbl}
              LIMIT {int(limit_rows)}"""

    out = []
    try:
        for ttl, ts_any, st, pc, ical in con.execute(sql):
            when = to_ms(ts_any)
            st_up = (st or "").upper()
            try: pc = int(pc or 0)
            except: pc = 0
            if (not ttl or when is None) and ical:
                txt = ics_unfold(ical)
                if "BEGIN:VTODO" in txt:
                    ttl = ttl or ics_val(ics_get_first(txt,"SUMMARY")) or "(No title)"
                    if when is None:
                        d = ics_val(ics_get_first(txt,"DUE"))
                        when = parse_ics_date(d)
                    if not st_up:
                        st_up = (ics_val(ics_get_first(txt,"STATUS")) or "").upper()
                    if pc == 0:
                        try: pc = int(ics_val(ics_get_first(txt,"PERCENT-COMPLETE")) or "0")
                        except: pc = 0
            out.append({"title": ttl or "(No title)", "dueMs": when, "done": (st_up=="COMPLETED") or (pc>=100), "src": src_label})
    except Exception:
        pass
    return out

def dedupe(items, key):
    seen=set(); out=[]
    for it in items:
        k = f"{it.get('title','')}|{it.get(key,'')}"
        if k in seen: continue
        seen.add(k); out.append(it)
    return out

def pretty(events, tasks):
    print("\n--- EVENTS ({}) ---".format(len(events)))
    if not events: print("(none)")
    else:
        for e in sorted(events, key=lambda x: (x.get("whenMs") is None, x.get("whenMs") or 0, x["title"])):
            print(f"{fmt_ms(e.get('whenMs'), e.get('allDay', False)):17} | {e['title']}")
    print("\n--- TASKS ({}) ---".format(len(tasks)))
    if not tasks: print("(none)")
    else:
        for t in sorted(tasks, key=lambda x: (x.get("dueMs") is None, x.get("dueMs")  or 0, x['title'])):
            tick = "[x]" if t.get("done") else "[ ]"
            print(f"{tick} {fmt_ms(t.get('dueMs')):17} | {t['title']}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true", help="Output JSON")
    ap.add_argument("--limit", type=int, default=ROW_LIMIT_DEFAULT)
    args = ap.parse_args()

    if not os.path.isdir(DB_DIR):
        print(json.dumps({"error":"calendar-data dir missing","dir":DB_DIR}) if args.json else f"[error] missing dir: {DB_DIR}")
        sys.exit(0)
    if not os.path.isfile(DB_PATH):
        print(json.dumps({"error":"local.sqlite missing","path":DB_PATH}) if args.json else f"[error] missing db: {DB_PATH}")
        sys.exit(0)

    log(f"[using] {DB_PATH}")
    snap, tmpdir = snapshot_db(DB_PATH)
    con = None
    try:
        con = open_immutable(snap)
        events = fetch_events(con, DB_PATH, args.limit)
        tasks  = fetch_tasks(con, DB_PATH, args.limit)
        events = dedupe(events, "whenMs")
        tasks  = dedupe(tasks,  "dueMs")
        for e in events: e["whenStr"] = fmt_ms(e.get("whenMs"), e.get("allDay", False))
        for t in tasks:  t["dueStr"]  = fmt_ms(t.get("dueMs"))
        if args.json:
            print(json.dumps({"events":events, "tasks":tasks}, ensure_ascii=False))
        else:
            pretty(events, tasks)
    finally:
        try:
            if con: con.close()
        finally:
            try: shutil.rmtree(tmpdir)
            except Exception: pass

if __name__ == "__main__":
    main()
