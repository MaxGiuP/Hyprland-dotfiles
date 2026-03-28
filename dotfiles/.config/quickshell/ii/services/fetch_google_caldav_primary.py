#!/usr/bin/env python3
import base64
import ctypes
import json
import re
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from ctypes import POINTER, Structure, byref, c_char, c_uint, c_void_p
from ctypes.util import find_library
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from fetch_thunderbird_calendar_all import copy_db, dedupe, discover_calendar_dbs, discover_profiles, read_db


GOOGLE_TOKEN_URL = "https://www.googleapis.com/oauth2/v3/token"
HARDCODED_GOOGLE_CLIENT_ID = "406964657835-aq8lmia8j95dhl1a2bvharmfk3t1hgqj.apps.googleusercontent.com"
HARDCODED_GOOGLE_CLIENT_SECRET = "kSmqreRr0qwBWJgbf5Y-PjSU"
LOCAL_TZ = datetime.now().astimezone().tzinfo or timezone.utc


class SECItem(Structure):
    _fields_ = [("type", c_uint), ("data", POINTER(c_char)), ("len", c_uint)]


def parse_pref_entries(profile_dir):
    prefs_path = profile_dir / "prefs.js"
    if not prefs_path.exists():
        return {}

    entries = {}
    pattern = re.compile(r'user_pref\("calendar\.registry\.([^.]+)\.([^"]+)",\s*(.+)\);')
    for line in prefs_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        match = pattern.match(line)
        if not match:
            continue
        calendar_id, key, raw_value = match.groups()
        raw_value = raw_value.strip()
        if raw_value.startswith('"') and raw_value.endswith('"'):
            value = raw_value[1:-1]
        elif raw_value == "true":
            value = True
        elif raw_value == "false":
            value = False
        else:
            value = raw_value
        entries.setdefault(calendar_id, {})[key] = value
    return entries


def discover_remote_calendars():
    candidates = []
    for profile_dir in discover_profiles():
        entries = parse_pref_entries(profile_dir)
        for calendar_id, info in entries.items():
            uri = str(info.get("uri", "") or "")
            username = str(info.get("username", "") or "")
            name = str(info.get("name", "") or "")
            cal_type = str(info.get("type", "") or "")
            if info.get("disabled") is True:
                continue
            if not info.get("calendar-main-in-composite", True):
                continue
            if cal_type == "gdata" and "?tasks=" in uri:
                continue
            if cal_type not in ("caldav", "gdata", "ics"):
                continue
            endpoint, backend = calendar_endpoint_from_info(info)
            auth_user = username or calendar_owner_from_uri(uri)
            if not endpoint:
                continue
            if backend in ("google-caldav", "caldav-basic") and not auth_user:
                continue
            score = 0
            if "default-release" in str(profile_dir):
                score += 5
            if name == auth_user:
                score += 10
            if cal_type == "caldav":
                score += 4
            candidates.append(
                {
                    "score": score,
                    "profile": profile_dir,
                    "calendarId": calendar_id,
                    "name": name,
                    "username": auth_user,
                    "uri": endpoint,
                    "type": cal_type,
                    "backend": backend,
                }
            )

    if not candidates:
        raise RuntimeError("No supported remote calendars found in Thunderbird prefs")

    best_profile = sorted(candidates, key=lambda item: item["score"], reverse=True)[0]["profile"]
    candidates = [item for item in candidates if item["profile"] == best_profile]
    ordered = sorted(candidates, key=lambda item: (item["score"], item["name"]), reverse=True)
    deduped = []
    seen = set()
    for item in ordered:
        key = (str(item["profile"]), item["username"], item["name"])
        if key in seen:
            continue
        deduped.append(item)
        seen.add(key)
    return deduped


def calendar_owner_from_uri(uri):
    if not uri.startswith("googleapi://"):
        return ""
    parsed = urllib.parse.urlparse(uri)
    return urllib.parse.unquote(parsed.netloc)


def calendar_endpoint_from_info(info):
    uri = str(info.get("uri", "") or "")
    cal_type = str(info.get("type", "") or "")
    if cal_type == "caldav" and uri.startswith("https://apidata.googleusercontent.com/caldav/v2/"):
        return uri.rstrip("/") + "/", "google-caldav"
    if cal_type == "caldav" and uri.startswith(("https://", "http://")):
        return uri.rstrip("/") + "/", "caldav-basic"
    if cal_type == "ics" and uri.startswith("webcal://"):
        return "https://" + uri[len("webcal://"):], "ics"
    if cal_type == "ics" and uri.startswith(("https://", "http://")):
        return uri, "ics"
    if cal_type != "gdata" or not uri.startswith("googleapi://"):
        return "", ""

    parsed = urllib.parse.urlparse(uri)
    query = urllib.parse.parse_qs(parsed.query)
    calendar_id = query.get("calendar", [""])[0]
    if not calendar_id:
        return "", ""
    return f"https://apidata.googleusercontent.com/caldav/v2/{calendar_id}/events/", "google-caldav"


def extract_google_oauth_client():
    omni_candidates = [
        Path("/usr/lib/thunderbird/omni.ja"),
        Path("/usr/lib64/thunderbird/omni.ja"),
    ]
    for omni_path in omni_candidates:
        if not omni_path.exists():
            continue
        try:
            with zipfile.ZipFile(omni_path) as zf:
                for member in ("modules/OAuth2Providers.sys.mjs", "modules/OAuth2Providers.sys.jsm"):
                    try:
                        text = zf.read(member).decode("utf-8", errors="ignore")
                    except KeyError:
                        continue
                    client_id = re.search(r'clientId:\s*"([^"]+apps\.googleusercontent\.com)"', text)
                    client_secret = re.search(r'clientSecret:\s*"([^"]+)"', text)
                    if client_id and client_secret:
                        return client_id.group(1), client_secret.group(1)
        except (OSError, zipfile.BadZipFile):
            continue
    return HARDCODED_GOOGLE_CLIENT_ID, HARDCODED_GOOGLE_CLIENT_SECRET


def load_nss():
    lib_name = find_library("nss3") or "libnss3.so"
    lib = ctypes.CDLL(lib_name)
    lib.NSS_Init.argtypes = [ctypes.c_char_p]
    lib.NSS_Init.restype = ctypes.c_int
    lib.NSS_Shutdown.argtypes = []
    lib.NSS_Shutdown.restype = ctypes.c_int
    lib.PK11SDR_Decrypt.argtypes = [POINTER(SECItem), POINTER(SECItem), c_void_p]
    lib.PK11SDR_Decrypt.restype = ctypes.c_int
    return lib


def decrypt_with_nss(profile_dir, ciphertext_b64):
    lib = load_nss()
    if lib.NSS_Init(str(profile_dir).encode()) != 0:
        raise RuntimeError(f"Failed to initialize NSS for {profile_dir}")

    try:
        raw = base64.b64decode(ciphertext_b64)
        input_buffer = ctypes.create_string_buffer(raw)
        input_item = SECItem(0, ctypes.cast(input_buffer, POINTER(c_char)), len(raw))
        output_item = SECItem()
        if lib.PK11SDR_Decrypt(byref(input_item), byref(output_item), None) != 0:
            raise RuntimeError("Failed to decrypt Thunderbird credential")
        return ctypes.string_at(output_item.data, output_item.len).decode("utf-8")
    finally:
        lib.NSS_Shutdown()


def load_google_refresh_token(profile_dir, target_username):
    logins_path = profile_dir / "logins.json"
    if not logins_path.exists():
        raise RuntimeError(f"Missing Thunderbird logins.json in {profile_dir}")

    payload = json.loads(logins_path.read_text(encoding="utf-8"))
    logins = payload.get("logins", [])

    preferred = []
    fallback = []
    for login in logins:
        hostname = login.get("hostname", "")
        if hostname == "oauth://accounts.google.com":
            preferred.append(login)
        elif hostname.startswith("oauth:") and target_username in hostname:
            fallback.append(login)

    for bucket in (preferred, fallback):
        for login in bucket:
            username = decrypt_with_nss(profile_dir, login["encryptedUsername"])
            password = decrypt_with_nss(profile_dir, login["encryptedPassword"])
            if username == target_username and password.startswith("1//"):
                return password

    raise RuntimeError(f"No usable Google OAuth refresh token found for {target_username}")


def load_matching_login(profile_dir, target_uri, target_username):
    logins_path = profile_dir / "logins.json"
    if not logins_path.exists():
        return None

    parsed_target = urllib.parse.urlparse(target_uri)
    payload = json.loads(logins_path.read_text(encoding="utf-8"))
    for login in payload.get("logins", []):
        hostname = login.get("hostname", "")
        if not hostname.startswith(("http://", "https://")):
            continue
        parsed_login = urllib.parse.urlparse(hostname)
        if parsed_login.netloc != parsed_target.netloc:
            continue
        username = decrypt_with_nss(profile_dir, login["encryptedUsername"])
        password = decrypt_with_nss(profile_dir, login["encryptedPassword"])
        if not target_username or username == target_username:
            return username, password
    return None


def exchange_refresh_token(refresh_token):
    client_id, client_secret = extract_google_oauth_client()
    body = urllib.parse.urlencode(
        {
            "client_id": client_id,
            "client_secret": client_secret,
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        GOOGLE_TOKEN_URL,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    token = payload.get("access_token", "")
    if not token:
        raise RuntimeError("Google OAuth token exchange did not return an access token")
    return token


def format_utc(dt):
    return dt.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def build_calendar_query(start_dt, end_dt):
    start_text = format_utc(start_dt)
    end_text = format_utc(end_dt)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data>
      <C:expand start="{start_text}" end="{end_text}"/>
    </C:calendar-data>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VEVENT">
        <C:time-range start="{start_text}" end="{end_text}"/>
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>""".encode("utf-8")


def fetch_caldav_events(calendar_info, headers, start_dt, end_dt):
    request = urllib.request.Request(
        calendar_info["uri"],
        data=build_calendar_query(start_dt, end_dt),
        headers=headers,
        method="REPORT",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read().decode("utf-8", errors="ignore")

    root = ET.fromstring(body)
    namespaces = {
        "d": "DAV:",
        "c": "urn:ietf:params:xml:ns:caldav",
    }
    event_payloads = []
    for node in root.findall(".//c:calendar-data", namespaces):
        if node.text and node.text.strip():
            event_payloads.append(node.text)

    events = []
    for raw_ics in event_payloads:
        events.extend(parse_ical_events(raw_ics, calendar_info))

    events = dedupe(events, ["externalId", "startAt", "title"])
    events.sort(key=lambda item: (item.get("startAt", 0), item.get("title", "").lower()))
    return events


def fetch_ics_events(calendar_info, start_dt, end_dt):
    request = urllib.request.Request(calendar_info["uri"], headers={"Accept": "text/calendar, text/plain;q=0.9, */*;q=0.1"})
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read().decode("utf-8", errors="ignore")
    events = parse_ical_events(body, calendar_info)
    events = [event for event in events if event.get("startAt", 0) < to_ms(end_dt) and event.get("endAt", 0) >= to_ms(start_dt)]
    events = dedupe(events, ["externalId", "startAt", "title"])
    events.sort(key=lambda item: (item.get("startAt", 0), item.get("title", "").lower()))
    return events


def unfold_ical_lines(text):
    unfolded = []
    for line in text.splitlines():
        if not line:
            continue
        if line.startswith((" ", "\t")) and unfolded:
            unfolded[-1] += line[1:]
        else:
            unfolded.append(line.rstrip("\r"))
    return unfolded


def parse_content_line(line):
    if ":" not in line:
        return None, {}, ""
    head, value = line.split(":", 1)
    parts = head.split(";")
    name = parts[0].upper()
    params = {}
    for part in parts[1:]:
        if "=" not in part:
            continue
        key, raw_value = part.split("=", 1)
        params[key.upper()] = raw_value.strip('"')
    return name, params, value


def parse_date_value(value):
    dt = datetime.strptime(value, "%Y%m%d")
    return datetime.combine(dt.date(), time.min, tzinfo=LOCAL_TZ), True


def parse_datetime_value(value, tzid):
    if value.endswith("Z"):
        return datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc), False

    if len(value) == 15:
        parsed = datetime.strptime(value, "%Y%m%dT%H%M%S")
    elif len(value) == 13:
        parsed = datetime.strptime(value, "%Y%m%dT%H%M")
    else:
        parsed = datetime.strptime(value, "%Y%m%dT%H%M%S")

    tzinfo = LOCAL_TZ
    if tzid and ZoneInfo is not None:
        try:
            tzinfo = ZoneInfo(tzid)
        except Exception:
            tzinfo = LOCAL_TZ
    return parsed.replace(tzinfo=tzinfo), False


def parse_ical_datetime(value, params):
    if not value:
        return None, False
    if params.get("VALUE", "").upper() == "DATE":
        return parse_date_value(value)
    return parse_datetime_value(value, params.get("TZID", ""))


def parse_ical_duration(value):
    sign = -1 if value.startswith("-") else 1
    text = value[1:] if value[:1] in "+-" else value
    pattern = re.compile(r"^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$")
    match = pattern.match(text)
    if not match:
        return None
    weeks, days, hours, minutes, seconds = (int(part or 0) for part in match.groups())
    delta = timedelta(weeks=weeks, days=days, hours=hours, minutes=minutes, seconds=seconds)
    return delta * sign


def to_ms(dt):
    return int(dt.timestamp() * 1000)


def parse_ical_events(raw_ics, calendar_info):
    lines = unfold_ical_lines(raw_ics)
    events = []
    current = None

    for line in lines:
        if line == "BEGIN:VEVENT":
            current = {}
            continue
        if line == "END:VEVENT":
            if current:
                event = build_event(current, calendar_info)
                if event:
                    events.append(event)
            current = None
            continue
        if current is None:
            continue

        name, params, value = parse_content_line(line)
        if not name:
            continue
        current[name] = (params, value)

    return events


def build_event(fields, calendar_info):
    summary = fields.get("SUMMARY", ({}, ""))[1].strip()
    status = fields.get("STATUS", ({}, ""))[1].strip().upper()
    uid = fields.get("UID", ({}, ""))[1].strip()
    dtstart = fields.get("DTSTART")
    if not summary or not uid or not dtstart or status == "CANCELLED":
        return None

    start_dt, all_day = parse_ical_datetime(dtstart[1], dtstart[0])
    if start_dt is None:
        return None

    end_dt = None
    dtend = fields.get("DTEND")
    if dtend:
        end_dt, _ = parse_ical_datetime(dtend[1], dtend[0])
    else:
        duration = fields.get("DURATION", ({}, ""))[1]
        if duration:
            delta = parse_ical_duration(duration)
            if delta is not None:
                end_dt = start_dt + delta

    if end_dt is None:
        end_dt = start_dt + (timedelta(days=1) if all_day else timedelta())

    return {
        "source": "google-caldav",
        "profile": str(calendar_info["profile"]),
        "dbPath": "",
        "calId": calendar_info["calendarId"],
        "calendarName": calendar_info["name"],
        "externalId": uid,
        "title": summary,
        "startAt": to_ms(start_dt),
        "endAt": to_ms(end_dt),
        "allDay": all_day,
        "startTz": getattr(start_dt.tzinfo, "key", str(start_dt.tzinfo or "")),
        "endTz": getattr(end_dt.tzinfo, "key", str(end_dt.tzinfo or "")),
        "lastModified": 0,
    }


def load_thunderbird_tasks():
    all_tasks = []
    profiles = []
    calendar_names = {}

    for profile_dir in discover_profiles():
        for calendar_id, info in parse_pref_entries(profile_dir).items():
            if info.get("disabled") is True:
                continue
            calendar_names[(str(profile_dir), calendar_id)] = str(info.get("name", "") or "")

    for profile_dir, src_db in discover_calendar_dbs():
        copied_db, tmp_dir = copy_db(src_db)
        if copied_db is None:
            continue
        profiles.append(str(profile_dir))
        try:
            tasks, _ = read_db(profile_dir, copied_db)
            for task in tasks:
                task["calendarName"] = calendar_names.get((task["profile"], task["calId"]), "")
            all_tasks.extend(tasks)
        finally:
            try:
                shutil.rmtree(tmp_dir)
            except OSError:
                pass

    all_tasks = dedupe(all_tasks, ["profile", "externalId", "calId"])
    all_tasks.sort(key=lambda item: (item.get("dueAt", 0) or item.get("entryAt", 0) or 0, item.get("content", "").lower()))
    return profiles, all_tasks


def main():
    profiles, tasks = load_thunderbird_tasks()
    calendars = discover_remote_calendars()
    now = datetime.now(tz=LOCAL_TZ)
    start_dt = datetime.combine((now - timedelta(days=31)).date(), time.min, tzinfo=LOCAL_TZ)
    end_dt = datetime.combine((now + timedelta(days=365)).date(), time.min, tzinfo=LOCAL_TZ)
    events = []
    errors = []
    auth_cache = {}

    for calendar in calendars:
        try:
            if calendar["backend"] == "google-caldav":
                username = calendar["username"]
                token_key = ("google", str(calendar["profile"]), username)
                access_token = auth_cache.get(token_key)
                if access_token is None:
                    refresh_token = load_google_refresh_token(calendar["profile"], username)
                    access_token = exchange_refresh_token(refresh_token)
                    auth_cache[token_key] = access_token
                headers = {
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": "application/xml; charset=utf-8",
                    "Depth": "1",
                }
                events.extend(fetch_caldav_events(calendar, headers, start_dt, end_dt))
            elif calendar["backend"] == "caldav-basic":
                login = load_matching_login(calendar["profile"], calendar["uri"], calendar["username"])
                if not login:
                    raise RuntimeError("No stored credential found for CalDAV calendar")
                username, password = login
                token = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
                headers = {
                    "Authorization": f"Basic {token}",
                    "Content-Type": "application/xml; charset=utf-8",
                    "Depth": "1",
                }
                events.extend(fetch_caldav_events(calendar, headers, start_dt, end_dt))
            elif calendar["backend"] == "ics":
                events.extend(fetch_ics_events(calendar, start_dt, end_dt))
            else:
                raise RuntimeError(f"Unsupported backend {calendar['backend']}")
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="ignore").strip()
            errors.append(f"{calendar['name']}: HTTP {exc.code} {detail}")
        except Exception as exc:
            errors.append(f"{calendar['name']}: {exc}")

    events = dedupe(events, ["calId", "externalId", "startAt", "title"])
    events.sort(key=lambda item: (item.get("startAt", 0), item.get("title", "").lower()))

    print(
        json.dumps(
            {
                "profile": str(calendars[0]["profile"]),
                "profiles": profiles,
                "tasks": tasks,
                "events": events,
                "error": " | ".join(errors),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="ignore").strip()
        print(json.dumps({"profile": "", "profiles": [], "tasks": [], "events": [], "error": f"Google CalDAV HTTP {exc.code}: {detail}"}))
        raise SystemExit(1)
    except Exception as exc:
        print(json.dumps({"profile": "", "profiles": [], "tasks": [], "events": [], "error": str(exc)}))
        raise SystemExit(1)
