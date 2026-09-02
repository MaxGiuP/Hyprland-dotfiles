#!/usr/bin/env python3

import datetime as dt
import importlib.util
import unittest
from pathlib import Path
from unittest import mock


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "fetch-quickmail-snapshot.py"
SPEC = importlib.util.spec_from_file_location("quickmail_sidebar_bridge", SCRIPT_PATH)
BRIDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BRIDGE)


class QuickMailSnapshotTests(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.binary = Path("/tmp/quickmailctl-test")
        self.now = dt.datetime(2026, 9, 2, 12, 0)
        self.snapshot = {
            "revision": 10,
            "accounts": [
                {
                    "id": "google-a",
                    "address": "calendar@google.test",
                    "provider": "gmail",
                    "taskWritable": True,
                },
                {
                    "id": "outlook-a",
                    "address": "calendar@outlook.test",
                    "provider": "outlook",
                    "taskWritable": True,
                },
            ],
            "recentMail": [],
            "tasks": [{"id": "short-task", "title": "Incomplete snapshot"}],
            "events": [{"id": "short-event", "title": "Incomplete snapshot"}],
            "sync": {},
        }
        self.tasks = [
            {
                "id": "google-task",
                "title": "Date-only task",
                "done": False,
                "dueAt": 1791158400000,
                "account": "google-a",
                "source": "google_tasks",
            },
            {
                "id": "outlook-task",
                "title": "Completed timed task",
                "done": True,
                "dueAt": 1791192600000,
                "account": "outlook-a",
                "source": "microsoft_todo",
            },
        ]
        self.events = [
            {
                "id": "future-event",
                "externalId": "provider-future",
                "calendarId": "outlook-a:primary",
                "calendarName": "Work",
                "title": "Beyond dashboard horizon",
                "startAt": 1798794000000,
                "endAt": 1798797600000,
                "allDay": False,
                "readOnly": True,
            },
            {
                "id": "all-day-event",
                "calendarId": "google-a:primary",
                "calendarName": "Personal",
                "title": "UTC date boundaries",
                "startAt": 1783641600000,
                "endAt": 1783728000000,
                "allDay": True,
                "readOnly": True,
            },
        ]

    def response_for(self, _binary, *arguments, **_kwargs):
        command = arguments[0]
        if command == "agenda-sync":
            return {"accepted": True, "errors": [], "revision": 11}
        if command == "snapshot":
            return self.snapshot
        if command == "tasks":
            return self.tasks
        if command == "events":
            return self.events
        raise AssertionError(f"Unexpected command: {arguments}")

    def test_authoritative_agenda_replaces_short_dashboard_lists(self):
        with mock.patch.object(BRIDGE, "run_cli", side_effect=self.response_for) as run_cli:
            result = BRIDGE.load_quickmail_data(
                self.binary,
                request_sync=True,
                now=self.now,
            )

        self.assertTrue(result["available"])
        self.assertEqual([task["id"] for task in result["tasks"]], [
            "google-task",
            "outlook-task",
        ])
        self.assertEqual([event["id"] for event in result["events"]], [
            "future-event",
            "all-day-event",
        ])
        self.assertTrue(result["tasks"][0]["dateOnly"])
        self.assertTrue(result["tasks"][1]["done"])
        self.assertEqual(result["events"][0]["accountId"], "outlook-a")
        self.assertEqual(result["events"][0]["startAt"], 1798794000000)
        self.assertEqual(result["events"][1]["endAt"], 1783728000000)
        self.assertTrue(result["events"][1]["allDay"])

        range_start, range_end = BRIDGE.agenda_range_ms(self.now)
        local_start = dt.datetime.fromtimestamp(range_start / 1000)
        local_end = dt.datetime.fromtimestamp(range_end / 1000)
        self.assertEqual(
            (local_start.year, local_start.month, local_start.day, local_start.hour),
            (2025, 1, 1, 0),
        )
        self.assertEqual(
            (local_end.year, local_end.month, local_end.day, local_end.hour),
            (2028, 1, 1, 0),
        )
        self.assertEqual(run_cli.call_args_list, [
            mock.call(
                self.binary,
                "agenda-sync",
                timeout=BRIDGE.AGENDA_SYNC_TIMEOUT_SECONDS,
            ),
            mock.call(self.binary, "snapshot"),
            mock.call(self.binary, "tasks", "--include-done"),
            mock.call(
                self.binary,
                "events",
                "--start-at",
                str(range_start),
                "--end-at",
                str(range_end),
            ),
        ])

    def test_partial_agenda_failure_keeps_snapshot_fallback(self):
        def partial_response(_binary, *arguments, **_kwargs):
            if arguments[0] == "snapshot":
                return self.snapshot
            if arguments[0] == "tasks":
                raise RuntimeError("task endpoint unavailable")
            if arguments[0] == "events":
                raise RuntimeError("calendar endpoint unavailable")
            raise AssertionError(f"Unexpected command: {arguments}")

        with mock.patch.object(BRIDGE, "run_cli", side_effect=partial_response):
            result = BRIDGE.load_quickmail_data(self.binary, now=self.now)

        self.assertEqual([task["id"] for task in result["tasks"]], ["short-task"])
        self.assertEqual([event["id"] for event in result["events"]], ["short-event"])
        self.assertIn("QuickMail tasks could not be refreshed", result["error"])
        self.assertIn("QuickMail events could not be refreshed", result["error"])

    def test_agenda_sync_account_error_is_visible(self):
        def sync_error_response(binary, *arguments, **kwargs):
            if arguments[0] == "agenda-sync":
                return {"accepted": True, "errors": [{"message": "Reconnect account"}]}
            return self.response_for(binary, *arguments, **kwargs)

        with mock.patch.object(BRIDGE, "run_cli", side_effect=sync_error_response):
            result = BRIDGE.load_quickmail_data(
                self.binary,
                request_sync=True,
                now=self.now,
            )

        self.assertEqual(result["error"], "QuickMail calendar: Reconnect account")

    def test_local_quickmail_task_remains_writable(self):
        snapshot = dict(self.snapshot)
        snapshot["tasks"] = [{
            "id": "local-task",
            "title": "Local",
            "source": "local",
            "account": "",
        }]
        result = BRIDGE.normalize(snapshot)

        self.assertTrue(result["tasks"][0]["writable"])
        self.assertFalse(result["tasks"][0]["readOnly"])
        self.assertEqual(result["tasks"][0]["originSource"], "local")


if __name__ == "__main__":
    unittest.main()
