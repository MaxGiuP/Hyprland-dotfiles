#!/usr/bin/env python3
"""Read account and recent-message metadata from Thunderbird's local index.

Thunderbird remains the credential owner. This script opens its search index
read-only and never reads message bodies, passwords, cookies, or OAuth tokens.
"""

import json
import sqlite3
import urllib.parse
from pathlib import Path


def newest_index():
    candidates = list((Path.home() / ".thunderbird").glob("*/global-messages-db.sqlite"))
    return max(candidates, key=lambda path: path.stat().st_mtime) if candidates else None


def account_from_uri(folder_uri):
    parsed = urllib.parse.urlparse(folder_uri)
    username = urllib.parse.unquote(parsed.username or "")
    host = (parsed.hostname or "").lower()
    if "gmail" in host or "googlemail" in host:
        provider = "Gmail"
    elif "outlook" in host or "office365" in host or "hotmail" in host:
        provider = "Microsoft"
    elif parsed.scheme == "pop":
        provider = "POP"
    else:
        provider = "IMAP"
    return {
        "id": f"{parsed.scheme}:{username}@{host}",
        "address": username or host,
        "host": host,
        "provider": provider,
        "protocol": parsed.scheme.upper(),
    }


def is_inbox(name, folder_uri):
    normalized_name = (name or "").strip().lower()
    normalized_uri = (folder_uri or "").lower().rstrip("/")
    return normalized_uri.endswith("/inbox") or normalized_name in {
        "inbox", "posta in arrivo", "boîte de réception", "posteingang"
    }


def message_flags(raw):
    try:
        attrs = json.loads(raw or "{}")
    except json.JSONDecodeError:
        attrs = {}
    return bool(attrs.get("59", False)), bool(attrs.get("58", False))


def main():
    db_path = newest_index()
    if db_path is None:
        print(json.dumps({"accounts": [], "messages": [], "error": "No Thunderbird mail index found"}))
        return

    uri = f"file:{urllib.parse.quote(str(db_path))}?mode=ro"
    connection = sqlite3.connect(uri, uri=True, timeout=1.0)
    connection.row_factory = sqlite3.Row

    folders = connection.execute(
        "SELECT id, folderURI, name FROM folderLocations WHERE folderURI LIKE 'imap:%' OR folderURI LIKE 'pop:%'"
    ).fetchall()
    inbox_ids = [row["id"] for row in folders if is_inbox(row["name"], row["folderURI"])]

    accounts = {}
    for folder in folders:
        account = account_from_uri(folder["folderURI"])
        accounts.setdefault(account["id"], {**account, "unread": 0, "total": 0})

    if inbox_ids:
        placeholders = ",".join("?" for _ in inbox_ids)
        count_rows = connection.execute(
            f"SELECT folderID, jsonAttributes FROM messages WHERE deleted=0 AND folderID IN ({placeholders})",
            inbox_ids,
        )
        folder_by_id = {row["id"]: row for row in folders}
        for row in count_rows:
            folder = folder_by_id.get(row["folderID"])
            if folder is None:
                continue
            account = account_from_uri(folder["folderURI"])
            read, _ = message_flags(row["jsonAttributes"])
            accounts[account["id"]]["total"] += 1
            if not read:
                accounts[account["id"]]["unread"] += 1

        recent_rows = connection.execute(
            f"""
            SELECT m.id, m.date, m.jsonAttributes, f.folderURI, f.name,
                   t.c1subject AS subject, t.c3author AS author
              FROM messages m
              JOIN folderLocations f ON f.id = m.folderID
              LEFT JOIN messagesText_content t ON t.docid = m.id
             WHERE m.deleted=0 AND m.folderID IN ({placeholders})
             ORDER BY m.date DESC
             LIMIT 30
            """,
            inbox_ids,
        ).fetchall()
    else:
        recent_rows = []

    messages = []
    for row in recent_rows:
        account = account_from_uri(row["folderURI"])
        read, starred = message_flags(row["jsonAttributes"])
        timestamp = int(row["date"] or 0)
        if timestamp > 10_000_000_000_000:
            timestamp //= 1000
        messages.append(
            {
                "id": str(row["id"]),
                "title": (row["subject"] or "(No subject)").strip(),
                "author": (row["author"] or "").strip(),
                "timestamp": timestamp,
                "read": read,
                "starred": starred,
                "account": account["address"],
                "accountId": account["id"],
                "provider": account["provider"],
            }
        )

    connection.close()
    ordered_accounts = sorted(accounts.values(), key=lambda item: (-item["unread"], item["address"].lower()))
    print(
        json.dumps(
            {
                "accounts": ordered_accounts,
                "messages": messages,
                "index": str(db_path.parent),
                "error": "",
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"accounts": [], "messages": [], "error": str(error)}))
