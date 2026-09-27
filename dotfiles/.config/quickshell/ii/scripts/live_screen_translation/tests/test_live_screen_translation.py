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
                for flag in ("-no-init", "-no-bidi", "-no-play", "-no-browser"):
                    self.assertIn(flag, command)
        with patch.object(backend, "run_command", return_value=subprocess.CompletedProcess([], 0, "", "Network failure")):
            with self.assertRaisesRegex(RuntimeError, "Translation unavailable"):
                backend.translate_text("hello", "en")

    def test_exact_source_sentences_remain_paired_when_target_punctuation_differs(self):
        translations = {"Hello there.": "Bonjour ! Salut !", "What now?": "Et maintenant"}
        with patch.object(backend, "translate_text", side_effect=lambda text, *_: translations[text]) as translate:
            worker = backend.AsyncTranslator("fr")
            try:
                worker.submit("Hello there. What now?")
                wait_for(lambda: worker._thread is None)
                result, error, segments = worker.snapshot_segments()
                self.assertEqual([(item["source"], item["translated"]) for item in segments],
                                 list(translations.items()))
                self.assertEqual(result, "Bonjour ! Salut !\nEt maintenant")
                self.assertEqual(error, "")
                self.assertTrue(all(not item["pending"] for item in segments))
                self.assertEqual(translate.call_count, 2)
            finally:
                worker.close()

    def test_unchanged_sentence_is_reused_and_only_changed_tail_is_pending(self):
        started, release = threading.Event(), threading.Event()
        calls = []

        def translate(text, *_):
            calls.append(text)
            if text == "A live tail keeps growing":
                started.set()
                release.wait(2)
            return text.upper()

        with patch.object(backend, "translate_text", side_effect=translate):
            worker = backend.AsyncTranslator("fr")
            try:
                worker.submit("Complete sentence. A live tail")
                wait_for(lambda: worker._thread is None)
                original = worker.snapshot_segments()[2]
                worker.submit("Complete sentence. A live tail keeps growing")
                self.assertTrue(started.wait(1))
                result, _, changed = worker.snapshot_segments()
                self.assertEqual([item["id"] for item in original], [item["id"] for item in changed])
                self.assertEqual(result, "COMPLETE SENTENCE.")
                self.assertFalse(changed[0]["pending"])
                self.assertTrue(changed[1]["pending"])
                self.assertEqual(changed[1]["translated"], "")
                release.set()
                wait_for(lambda: worker._thread is None)
                self.assertEqual(calls.count("Complete sentence."), 1)
                self.assertEqual(len(calls), 3)
            finally:
                release.set()
                worker.close()

    def test_sliding_source_preserves_colours_and_translation_cache_is_bounded(self):
        with patch.object(backend, "translate_text", side_effect=lambda text, *_: text.upper()):
            worker = backend.AsyncTranslator("fr")
            worker.CACHE_LIMIT = 6
            try:
                worker.submit("First sentence. Second sentence. Third sentence.")
                wait_for(lambda: worker._thread is None)
                original = worker.snapshot_segments()[2]
                worker.submit("Second sentence. Third sentence. Fourth sentence.")
                wait_for(lambda: worker._thread is None)
                changed = worker.snapshot_segments()[2]
                self.assertEqual([item["id"] for item in original[1:]],
                                 [item["id"] for item in changed[:2]])
                for index in range(10):
                    worker.submit(f"Unique phrase {index}.")
                    wait_for(lambda: worker._thread is None)
                self.assertEqual(len(worker._cache), 6)
                worker.reset()
                self.assertEqual(worker.snapshot_segments(), ("", "", []))
            finally:
                worker.close()

    def test_many_sentences_keep_only_twelve_recent_pairs_and_requests(self):
        with patch.object(backend, "translate_text", side_effect=lambda text, *_: text.upper()) as translate:
            worker = backend.AsyncTranslator("fr")
            try:
                worker.submit(" ".join(f"Sentence {index}." for index in range(20)))
                wait_for(lambda: worker._thread is None)
                self.assertEqual(len(worker.snapshot_segments()[2]), 12)
                self.assertEqual(translate.call_count, 12)
                self.assertEqual(worker.snapshot_segments()[2][0]["source"], "Sentence 8.")
            finally:
                worker.close()

    def test_two_requests_overlap_without_exceeding_limit_or_duplicating_sources(self):
        release = threading.Event()
        lock = threading.Lock()
        calls = []
        active = peak = 0

        def translate(text, *_):
            nonlocal active, peak
            with lock:
                calls.append(text)
                active += 1
                peak = max(peak, active)
            release.wait(2)
            with lock:
                active -= 1
            return text.upper()

        with patch.object(backend, "translate_text", side_effect=translate):
            worker = backend.AsyncTranslator("fr")
            try:
                text = "First sentence. Second sentence. Third sentence."
                worker.submit(text)
                wait_for(lambda: len(calls) == 2)
                for _ in range(5):
                    worker.submit(text)
                self.assertEqual(len(calls), 2)
                release.set()
                wait_for(lambda: worker._thread is None)
                self.assertEqual(peak, 2)
                self.assertCountEqual(calls, ["First sentence.", "Second sentence.", "Third sentence."])
                self.assertEqual(worker.result(), "FIRST SENTENCE.\nSECOND SENTENCE.\nTHIRD SENTENCE.")
            finally:
                release.set()
                worker.close()

    def test_sentence_mode_retains_context_and_phrase_mode_keeps_inline_separators(self):
        text = "I opened the settings panel, and I changed the font size."
        with patch.object(backend, "translate_text", side_effect=lambda text, *_: text.upper()) as translate:
            worker = backend.AsyncTranslator("fr", granularity="sentence")
            try:
                worker.submit(text)
                wait_for(lambda: worker._thread is None)
                self.assertEqual(translate.call_count, 1)
                self.assertEqual(worker.result(), text.upper())
            finally:
                worker.close()
            worker = backend.AsyncTranslator("fr", granularity="phrase")
            try:
                worker.submit(text)
                wait_for(lambda: worker._thread is None)
                segments = worker.snapshot_segments()[2]
                self.assertGreater(len(segments), 1)
                self.assertEqual(worker.result(), text.upper())
                self.assertTrue(all(item["separator"] == " " for item in segments[1:]))
            finally:
                worker.close()

    def test_close_interrupts_both_active_translation_requests(self):
        started = []

        def translate(text, language, stop_event):
            started.append(text)
            stop_event.wait(2)
            return ""

        with patch.object(backend, "translate_text", side_effect=translate):
            worker = backend.AsyncTranslator("fr")
            worker.submit("First sentence. Second sentence.")
            wait_for(lambda: len(started) == 2)
            worker.close()
            self.assertIsNone(worker._thread)
            self.assertEqual(worker.snapshot_segments(), ("", "", []))

    def test_pending_sentence_beginning_does_not_join_its_tail_to_previous_sentence(self):
        release = threading.Event()

        def translate(text, *_):
            if text == "I opened the settings panel,":
                release.wait(2)
            return text.upper()

        with patch.object(backend, "translate_text", side_effect=translate):
            worker = backend.AsyncTranslator("fr")
            try:
                worker.submit("First sentence. I opened the settings panel, and I changed the font size.")
                wait_for(lambda: len(worker._cache) == 2)
                self.assertEqual(worker.result(), "FIRST SENTENCE.\nAND I CHANGED THE FONT SIZE.")
                segments = worker.snapshot_segments()[2]
                self.assertTrue(segments[1]["pending"])
                self.assertFalse(segments[2]["pending"])
            finally:
                release.set()
                worker.close()


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

    def test_wrapped_lines_rejoin_in_reading_order_with_paragraph_boundaries(self):
        tsv = ("level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tconf\ttext\n"
               "5\t1\t1\t1\t2\t1\t90\tcontext.\n"
               "5\t1\t1\t1\t1\t2\t90\tsentence\n"
               "5\t1\t1\t1\t1\t1\t90\tFull\n"
               "5\t1\t1\t2\t1\t1\t90\tNext.\n"
               "5\t1\t2\t1\t1\t1\t90\tSeparate.\n")
        with patch.object(backend, "run_command", return_value=subprocess.CompletedProcess([], 0, tsv.encode(), b"")):
            self.assertEqual(backend.ocr_image(b"synthetic", "eng"),
                             ("Full sentence context.\nNext.\nSeparate.", 90.0))

    def test_identical_capture_reuses_ocr_but_image_or_language_change_reprocesses(self):
        cache = backend.OcrFrameCache()
        with tempfile.TemporaryDirectory() as temp, \
             patch.object(backend, "preprocess_image", return_value=b"processed") as preprocess, \
             patch.object(backend, "ocr_image", side_effect=[("first", 90), ("changed", 80), ("French", 95)]) as ocr:
            image = Path(temp) / "capture.png"
            image.write_bytes(b"first PNG")
            self.assertEqual(cache.read(image, "eng"), ("first", 90))
            self.assertEqual(cache.read(image, "eng"), ("first", 90))
            self.assertEqual(ocr.call_count, 1)
            image.write_bytes(b"changed PNG")
            self.assertEqual(cache.read(image, "eng"), ("changed", 80))
            self.assertEqual(cache.read(image, "fra"), ("French", 95))
            self.assertEqual(preprocess.call_count, 3)

    def test_failed_ocr_retries_an_unchanged_capture(self):
        cache = backend.OcrFrameCache()
        with tempfile.TemporaryDirectory() as temp, \
             patch.object(backend, "preprocess_image", return_value=b"processed"), \
             patch.object(backend, "ocr_image", side_effect=[RuntimeError("temporary"), ("recovered", 90)]) as ocr:
            image = Path(temp) / "capture.png"
            image.write_bytes(b"same PNG")
            with self.assertRaisesRegex(RuntimeError, "temporary"):
                cache.read(image, "eng")
            self.assertEqual(cache.read(image, "eng"), ("recovered", 90))
            self.assertEqual(ocr.call_count, 2)

    def test_capture_period_accounts_for_processing_and_bounds_failure_retries(self):
        with patch.object(backend.time, "monotonic", return_value=10.4):
            self.assertAlmostEqual(backend.capture_wait_seconds(10.0, 0.6), 0.2)
        with patch.object(backend.time, "monotonic", return_value=10.9):
            self.assertEqual(backend.capture_wait_seconds(10.0, 0.6), 0)
            self.assertEqual(backend.capture_wait_seconds(10.0, 0.6, failed=True), 0.1)


class MainLoopTests(unittest.TestCase):
    def run_frames(self, frames, images=None, delayed_translation=False):
        backend.STOP_REQUESTED.clear()
        states = []
        with tempfile.TemporaryDirectory() as temp:
            args = argparse.Namespace(state_file=str(Path(temp) / "state.json"), region="-10,0 100x40",
                                      target_language="en", ocr_language="eng", interval_seconds=0.1,
                                      confidence_threshold=60, translation_granularity="phrase")
            # Fake translator results make frame/state timing deterministic.
            class Translator:
                def __init__(self, language, granularity="phrase"):
                    self.text = ""
                    self.submits = 0
                def submit(self, text):
                    self.text = text
                    self.submits += 1
                def reset(self): self.text = ""
                def snapshot(self): return self.result(), ""
                def snapshot_segments(self):
                    return self.result(), "", ([{"id": "test", "source": self.text,
                                                     "translated": self.result(), "pending": not bool(self.result())}]
                                                   if self.text else [])
                def result(self): return "" if delayed_translation and self.submits < 2 else self.text.upper()
                def close(self): pass

            waits = 0
            captures = 0

            def capture(region, image_path):
                nonlocal captures
                image_path.write_bytes(images[captures] if images else f"frame {captures}".encode())
                captures += 1

            def wait(_):
                nonlocal waits
                waits += 1
                if waits >= len(frames):
                    backend.STOP_REQUESTED.set()

            with patch.object(backend, "parse_args", return_value=args), \
                 patch.object(backend, "capture_region", side_effect=capture), \
                 patch.object(backend, "preprocess_image", return_value=b"synthetic"), \
                 patch.object(backend, "ocr_image", side_effect=frames) as ocr, \
                 patch.object(backend, "AsyncTranslator", Translator), \
                 patch.object(backend, "write_state", side_effect=lambda path, state: states.append(state.copy())), \
                 patch.object(backend.STOP_REQUESTED, "wait", side_effect=wait):
                self.assertEqual(backend.main(), 0)
                self.ocr_calls = ocr.call_count
        backend.STOP_REQUESTED.clear()
        return states[2:-1]

    def test_blank_selection_clears_stale_text_after_two_frames(self):
        states = self.run_frames([("hello", 90), ("", 0), ("", 0)])
        self.assertEqual([state["ocr_text"] for state in states], ["hello", "hello", ""])
        self.assertEqual(states[-1]["translated_text"], "")
        self.assertEqual(states[-1]["translation_segments"], [])

    def test_low_confidence_frames_still_publish_current_translation(self):
        states = self.run_frames([("hello", 90), ("noise", 10)])
        self.assertEqual(len(states), 2)
        self.assertEqual(states[-1]["ocr_text"], "hello")
        self.assertEqual(states[-1]["translated_text"], "HELLO")

    def test_unchanged_frames_still_publish_state_and_clear_blank_selection(self):
        states = self.run_frames([("hello", 90), ("", 0), ("unused", 0)],
                                 images=[b"text image", b"blank image", b"blank image"])
        self.assertEqual(self.ocr_calls, 2)
        self.assertEqual(len(states), 3)
        self.assertEqual([state["ocr_text"] for state in states], ["hello", "hello", ""])
        self.assertEqual(states[-1]["translation_segments"], [])

    def test_cached_ocr_still_publishes_newly_completed_translation(self):
        states = self.run_frames([("hello", 90), ("unused", 0)],
                                 images=[b"same image", b"same image"], delayed_translation=True)
        self.assertEqual(self.ocr_calls, 1)
        self.assertEqual([state["translated_text"] for state in states], ["", "HELLO"])
        self.assertFalse(states[-1]["translation_segments"][0]["pending"])

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
