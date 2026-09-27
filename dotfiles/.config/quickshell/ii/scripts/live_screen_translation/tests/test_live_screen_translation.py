"""Offline regressions: synthetic OCR/processes only, with no screen capture or network."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "live_screen_translation.py"
SPEC = importlib.util.spec_from_file_location("live_screen_translation", SCRIPT)
backend = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend)


def wait_for(predicate, timeout=2):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.005)
    raise AssertionError("Background worker did not finish")


class GeometryTests(unittest.TestCase):
    def test_regions_on_monitors_left_of_and_above_primary(self):
        self.assertEqual(backend.normalize_geometry(" -1920,-1080  640x240 "), "-1920,-1080 640x240")
        self.assertEqual(backend.normalize_geometry("-10.4,20.7 640.2x240.8"), "-10,21 640x241")
        self.assertEqual(backend.normalize_geometry("+10,+20 640x240"), "10,20 640x240")

    def test_invalid_regions_are_rejected(self):
        for region in ("0,0 0x20", "0,0 20x0", "0,0 -20x10", "0,0 2..0x10", "nan,0 20x10"):
            with self.subTest(region=region), self.assertRaises(ValueError):
                backend.normalize_geometry(region)


class TranslatorTests(unittest.TestCase):
    def setUp(self):
        backend.STOP_REQUESTED.clear()

    def test_latest_queued_text_runs_without_another_submit(self):
        started, release = threading.Event(), threading.Event()
        calls = []

        def translate(text, language, stop_event):
            calls.append(text)
            if text == "first":
                started.set()
                release.wait(2)
            return text.upper()

        with patch.object(backend, "translate_text", side_effect=translate):
            worker = backend.AsyncTranslator("en")
            try:
                worker.submit("first")
                self.assertTrue(started.wait(1))
                worker.submit("discarded intermediate")
                worker.submit("latest")
                release.set()
                wait_for(lambda: worker.result() == "LATEST")
                self.assertEqual(calls, ["first", "latest"])
            finally:
                release.set()
                worker.close()

    def test_old_translation_never_appears_with_new_source(self):
        started, release = threading.Event(), threading.Event()

        def translate(text, language, stop_event):
            if text == "new":
                started.set()
                release.wait(2)
            return text.upper()

        with patch.object(backend, "translate_text", side_effect=translate):
            worker = backend.AsyncTranslator("en")
            try:
                worker.submit("old")
                wait_for(lambda: worker.result() == "OLD")
                worker.submit("new")
                self.assertTrue(started.wait(1))
                self.assertEqual(worker.result(), "")
            finally:
                release.set()
                worker.close()

    def test_reset_discards_in_flight_result(self):
        started, release = threading.Event(), threading.Event()

        def translate(text, language, stop_event):
            started.set()
            release.wait(2)
            return "stale translation"

        with patch.object(backend, "translate_text", side_effect=translate):
            worker = backend.AsyncTranslator("en")
            try:
                worker.submit("old")
                self.assertTrue(started.wait(1))
                worker.reset()
                release.set()
                wait_for(lambda: worker._thread is None)
                self.assertEqual(worker.result(), "")
            finally:
                release.set()
                worker.close()

    def test_unchanged_text_retries_after_temporary_failure(self):
        with patch.object(backend, "translate_text", side_effect=[RuntimeError("Offline"), "Recovered"]) as translate:
            worker = backend.AsyncTranslator("en")
            try:
                worker.submit("same text")
                wait_for(lambda: worker._thread is None)
                self.assertEqual(worker.snapshot(), ("", "Offline"))
                worker.submit("same text")
                self.assertEqual(translate.call_count, 1)
                with worker._lock:
                    worker._retry_after = 0
                worker.submit("same text")
                wait_for(lambda: worker.result() == "Recovered")
                worker.submit("same text")
                self.assertEqual(translate.call_count, 2)
            finally:
                worker.close()

    def test_input_is_literal_and_diagnostics_are_not_a_translation(self):
        with patch.object(backend, "run_command", return_value=subprocess.CompletedProcess([], 0, "hello\n", "")) as run:
            for text in ("-help", "file:///private-example", "https://example.invalid"):
                self.assertEqual(backend.translate_text(text, "en"), "hello")
                command = run.call_args.args[0]
                self.assertEqual(command[-2:], ["--", " " + text])
        with patch.object(backend, "run_command", return_value=subprocess.CompletedProcess([], 0, "", "Network failure")):
            with self.assertRaisesRegex(RuntimeError, "Translation unavailable"):
                backend.translate_text("hello", "en")


class OcrTests(unittest.TestCase):
    def test_quotes_and_malformed_rows_do_not_corrupt_other_words(self):
        tsv = ("level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tconf\ttext\n"
               '5\t1\t1\t1\t1\t1\t95\t"Hello\n'
               '5\t1\t1\t1\t1\t2\t85\tworld"\n'
               "5\t1\t1\t1\t1\t3\tnan\tbad\n"
               "5\t1\tbad\t1\t1\t3\t90\tmalformed\n"
               "5\t1\t1\t1\t1\t4\t101\timpossible\n")
        with patch.object(backend, "run_command", return_value=subprocess.CompletedProcess([], 0, tsv.encode(), b"")):
            self.assertEqual(backend.ocr_image(b"synthetic", "eng"), ('"Hello world"', 90.0))


class MainLoopTests(unittest.TestCase):
    def run_frames(self, frames):
        backend.STOP_REQUESTED.clear()
        states = []
        with tempfile.TemporaryDirectory() as temp:
            args = argparse.Namespace(state_file=str(Path(temp) / "state.json"), region="-10,0 100x40",
                                      target_language="en", ocr_language="eng", interval_seconds=0.1,
                                      confidence_threshold=60)
            # Fake translator results make frame/state timing deterministic.
            class Translator:
                def __init__(self, language): self.text = ""
                def submit(self, text): self.text = text
                def reset(self): self.text = ""
                def snapshot(self): return self.text.upper(), ""
                def result(self): return self.text.upper()
                def close(self): pass

            waits = 0
            def wait(_):
                nonlocal waits
                waits += 1
                if waits >= len(frames):
                    backend.STOP_REQUESTED.set()

            with patch.object(backend, "parse_args", return_value=args), \
                 patch.object(backend, "capture_region"), \
                 patch.object(backend, "preprocess_image", return_value=b"synthetic"), \
                 patch.object(backend, "ocr_image", side_effect=frames), \
                 patch.object(backend, "AsyncTranslator", Translator), \
                 patch.object(backend, "write_state", side_effect=lambda path, state: states.append(state.copy())), \
                 patch.object(backend.STOP_REQUESTED, "wait", side_effect=wait):
                self.assertEqual(backend.main(), 0)
        backend.STOP_REQUESTED.clear()
        return states[2:-1]

    def test_blank_selection_clears_stale_text_after_two_frames(self):
        states = self.run_frames([("hello", 90), ("", 0), ("", 0)])
        self.assertEqual([state["ocr_text"] for state in states], ["hello", "hello", ""])
        self.assertEqual(states[-1]["translated_text"], "")

    def test_low_confidence_frames_still_publish_current_translation(self):
        states = self.run_frames([("hello", 90), ("noise", 10)])
        self.assertEqual(len(states), 2)
        self.assertEqual(states[-1]["ocr_text"], "hello")
        self.assertEqual(states[-1]["translated_text"], "HELLO")

    def test_successful_low_confidence_capture_clears_previous_ocr_error(self):
        states = self.run_frames([("hello", 90), RuntimeError("Synthetic OCR failure"), ("noise", 10)])
        self.assertEqual([state["status"] for state in states], ["running", "error", "running"])
        self.assertEqual(states[-1]["ocr_text"], "hello")

    def test_state_file_is_private_and_valid_json(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "state.json"
            backend.write_state(path, {"translated_text": "Café"})
            self.assertEqual(json.loads(path.read_text()), {"translated_text": "Café"})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(path.parent.iterdir()), [path])


class ProcessTests(unittest.TestCase):
    def setUp(self):
        backend.STOP_REQUESTED.clear()

    def test_timeout_reaps_subprocess(self):
        with tempfile.TemporaryDirectory() as temp:
            pid_file = Path(temp) / "pid"
            command = [sys.executable, "-c",
                       "import os, pathlib, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)",
                       str(pid_file)]
            with self.assertRaises(subprocess.TimeoutExpired):
                backend.run_command(command, timeout=0.5)
            pid = int(pid_file.read_text())
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)

    def test_cancellation_interrupts_running_process(self):
        stop = threading.Event()
        errors = []
        with tempfile.TemporaryDirectory() as temp:
            pid_file = Path(temp) / "pid"
            command = [sys.executable, "-c",
                       "import os, pathlib, sys, time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)",
                       str(pid_file)]
            def run():
                try:
                    backend.run_command(command, timeout=60, stop_event=stop)
                except backend.ProcessCancelled:
                    errors.append("cancelled")
            thread = threading.Thread(target=run)
            thread.start()
            try:
                wait_for(lambda: pid_file.exists() and pid_file.read_text())
            finally:
                stop.set()
                thread.join(2)
            self.assertFalse(thread.is_alive())
            self.assertEqual(errors, ["cancelled"])
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pid_file.read_text()), 0)


if __name__ == "__main__":
    unittest.main()
