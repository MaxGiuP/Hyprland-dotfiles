"""Growing captions must display useful, correctly paired results during speech."""
import threading
import time
import unittest
from unittest.mock import patch

import live_captions as captions
from literal_translation import _source_tokens
from translation_segments import SegmentTracker


def wait_for(predicate):
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.005)
    raise AssertionError("Timed out waiting for translation")


class GrowingTranslationTests(unittest.TestCase):
    def test_natural_results_appear_while_source_keeps_growing(self):
        def provider(text, *args):
            time.sleep(.06)
            return "TARGET:" + text
        with patch.object(captions, "translate_text", side_effect=provider):
            worker = captions.AsyncTranslator()
            tracker = SegmentTracker(granularity="sentence")
            visible_during_growth = []
            try:
                words = []
                for index in range(24):
                    words.append("word" + str(index))
                    _, _, _, pairs = captions.paired_translations(
                        worker, tracker, " ".join(words), "", "de", "en")
                    pair = pairs[-1]
                    if pair["translated"]:
                        visible_during_growth.append(index)
                        self.assertTrue(pair["source"].startswith(pair["translated_source"]))
                        self.assertEqual(pair["translated"], "TARGET:" + pair["translated_source"])
                        self.assertTrue(pair["pending"])
                    time.sleep(.015)
                self.assertGreater(len(visible_during_growth), 10)
            finally:
                worker.stop()

    def test_literal_progress_is_visible_before_provider_returns(self):
        progress, release = threading.Event(), threading.Event()
        def provider(text, target, source, stop, *, on_progress, cache):
            on_progress({"source": "Er hat", "translated": "He has", "complete": False})
            progress.set()
            release.wait(2)
            return "He has yesterday there worked."
        with patch.object(captions, "translate_literal", side_effect=provider):
            worker = captions.AsyncTranslator("literal")
            tracker = SegmentTracker(granularity="sentence")
            def snapshot(text="Er hat gestern dort gearbeitet."):
                return captions.paired_translations(worker, tracker, text, "", "en", "de")[3][0]
            try:
                snapshot()
                self.assertTrue(progress.wait(1))
                pair = snapshot()
                self.assertEqual(pair["translated_source"], "Er hat")
                self.assertEqual(pair["translated"], "He has")
                self.assertTrue(pair["pending"])
                self.assertEqual(snapshot("Sie hat gestern dort gearbeitet.")["translated"], "")
                release.set()
            finally:
                release.set()
                worker.stop()

    def test_prefix_reuse_rejects_changed_words_languages_and_half_words(self):
        with patch.object(captions, "translate_text", return_value=""):
            worker = captions.AsyncTranslator()
            try:
                with worker._lock:
                    worker._cache[("a cat", "de", "en")] = "eine Katze"
                self.assertEqual(worker.request_snapshot("a cat sleeps", "de", "en")["translated"], "eine Katze")
                for text, target, source in [("a caterpillar", "de", "en"),
                                             ("a cat\u0301", "de", "en"),
                                             ("a cat\u2010like", "de", "en"),
                                             ("a dog sleeps", "de", "en"),
                                             ("a cat sleeps", "fr", "en"),
                                             ("a cat sleeps", "de", "fr")]:
                    self.assertEqual(worker.request_snapshot(text, target, source)["translated"], "")
            finally:
                worker.stop()

    def test_literal_growth_keeps_context_sensitive_tail_revisable(self):
        first_source = "Er hat gestern dort ein Buch"
        glosses = dict(enumerate(["He", "has", "yesterday", "there", "a", "book"]))
        entered, release = threading.Event(), threading.Event()
        def provider(text, target, source, stop, *, on_progress, cache):
            if text == first_source:
                cache._store(text, target, source, _source_tokens(text), glosses, True)
                return "He has yesterday there a book"
            entered.set()
            release.wait(2)
            return "He has yesterday there a book read"
        with patch.object(captions, "translate_literal", side_effect=provider):
            worker = captions.AsyncTranslator("literal")
            try:
                wait_for(lambda: worker.request_snapshot(first_source, "en", "de")["complete"])
                snapshot = worker.request_snapshot(first_source + " gelesen", "en", "de")
                self.assertTrue(entered.wait(1))
                self.assertEqual(snapshot, {"source": "Er hat gestern", "translated": "He has yesterday", "complete": False})
            finally:
                release.set()
                worker.stop()

    def test_partial_failure_keeps_valid_completed_words(self):
        def provider(text, target, source, stop, *, on_progress, cache):
            on_progress({"source": "Er hat", "translated": "He has", "complete": False})
            raise RuntimeError("Connection interrupted")
        with patch.object(captions, "translate_literal", side_effect=provider):
            worker = captions.AsyncTranslator("literal")
            try:
                worker.request_snapshot("Er hat gelesen.", "en", "de")
                wait_for(worker.error)
                result = worker.request_snapshot("Er hat gelesen.", "en", "de")
                self.assertEqual(result, {"source": "Er hat", "translated": "He has", "complete": False})
            finally:
                worker.stop()
            self.assertEqual(worker.request_snapshot("Er hat gelesen.", "en", "de")["translated"], "")

    def test_unrelated_edit_cancels_old_literal_request_promptly(self):
        started, cancelled = threading.Event(), threading.Event()
        def provider(text, target, source, stop, **kwargs):
            if text == "Old words":
                started.set()
                if stop.wait(1):
                    cancelled.set()
                raise RuntimeError("Cancelled")
            return "New translation"
        with patch.object(captions, "translate_literal", side_effect=provider):
            worker = captions.AsyncTranslator("literal")
            try:
                worker.request_snapshot("Old words", "de", "en")
                self.assertTrue(started.wait(1))
                worker.request_snapshot("Revised words", "de", "en")
                self.assertTrue(cancelled.wait(.5))
                wait_for(lambda: worker.request_snapshot("Revised words", "de", "en")["complete"])
                self.assertEqual(worker.error(), "")
            finally:
                worker.stop()

    def test_scroll_out_cancels_literal_request(self):
        started, cancelled = threading.Event(), threading.Event()
        def provider(text, target, source, stop, **kwargs):
            started.set()
            if stop.wait(1):
                cancelled.set()
            return ""
        with patch.object(captions, "translate_literal", side_effect=provider):
            worker = captions.AsyncTranslator("literal")
            try:
                worker.request_snapshot("Old words", "de", "en")
                self.assertTrue(started.wait(1))
                worker.retain_streams(set())
                self.assertTrue(cancelled.wait(.5))
                self.assertEqual(worker.error(), "")
            finally:
                worker.stop()

    def test_repeated_asr_tail_revisions_do_not_starve_unchanged_prefix(self):
        started, cancelled, visible = [], [], []

        def provider(text, target, source, stop, *, on_progress, cache):
            started.append(text)
            if stop.wait(.08):
                cancelled.append(text)
                raise RuntimeError("Cancelled")
            tokens = _source_tokens(text)
            glosses = {token["id"]: token["source"].upper() for token in tokens}
            cache._store(text, target, source, tokens, glosses, True)
            on_progress({"source": text, "translated": text.upper(), "complete": True})
            return text.upper()

        with patch.object(captions, "translate_literal", side_effect=provider):
            worker = captions.AsyncTranslator("literal")
            try:
                for index in range(30):
                    text = "I have already read the book and I will bring it " + (
                        "tomorrow" if index % 2 else "tonight")
                    snapshot = worker.request_snapshot(text, "de", "en")
                    if snapshot["translated"]:
                        visible.append(snapshot)
                        self.assertTrue(text.startswith(snapshot["source"]))
                        self.assertEqual(snapshot["translated"], snapshot["source"].upper())
                    time.sleep(.015)
                self.assertGreater(len(visible), 10)
                self.assertEqual(cancelled, [])
                self.assertLessEqual(len(started), 3)
            finally:
                worker.stop()

    def test_cached_fast_return_cannot_escape_a_concurrent_stop(self):
        worker = captions.AsyncTranslator()
        try:
            with worker._lock:
                worker._cache[("a cat", "de", "en")] = "eine Katze"
            original_request = worker.request

            def request_then_stop(*args, **kwargs):
                result = original_request(*args, **kwargs)
                worker.stop()
                return result

            with patch.object(worker, "request", side_effect=request_then_stop):
                self.assertEqual(worker.request_snapshot("a cat", "de", "en"),
                                 {"source": "", "translated": "", "complete": False})
        finally:
            worker.stop()


if __name__ == "__main__":
    unittest.main()
