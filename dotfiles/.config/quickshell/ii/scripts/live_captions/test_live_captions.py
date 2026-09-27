"""Offline regression tests; no microphones, models, or translation services are used."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import numpy as np

import live_captions as captions


def wait_for(predicate, timeout=2):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.005)
    raise AssertionError("Timed out waiting for background work")


class CaptionTextTests(unittest.TestCase):
    def test_state_replacement_is_private_and_leaves_no_temporary_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            captions.write_state(path, {"current_text": "hello"})
            captions.write_state(path, {"current_text": "bonjour"})
            self.assertEqual(json.loads(path.read_text()), {"current_text": "bonjour"})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(Path(directory).iterdir()), [path])

    def test_merge_uses_words_not_substrings(self):
        self.assertEqual(captions.merge_continuous_text("he", "the answer"), "he the answer")
        self.assertEqual(captions.merge_continuous_text("Hello, world.", "world again"), "Hello, world. again")

    def test_explicit_timing_overrides_preset(self):
        args = argparse.Namespace(preset="accurate", step_seconds=0.5)
        captions.apply_preset(args)
        self.assertEqual(args.step_seconds, 0.5)
        self.assertEqual(args.commit_ratio, captions.PRESET_DEFAULTS["accurate"]["commit_ratio"])

    def test_translations_do_not_duplicate_stable_prefix(self):
        translator = Mock()
        translator.request.side_effect = ["Bonjour", "Bonjour tout le monde"]
        self.assertEqual(
            captions.translated_texts(translator, "Hello everybody", "Hello", "fr", "en"),
            ("Bonjour tout le monde", "Bonjour", "tout le monde"),
        )

    def test_reordered_translation_appears_once(self):
        translator = Mock()
        translator.request.side_effect = ["Ich mag", "Das mag ich"]
        self.assertEqual(
            captions.translated_texts(translator, "I like that", "I like", "de", "en"),
            ("Das mag ich", "", "Das mag ich"),
        )

    def test_vosk_keeps_repeated_separate_utterances(self):
        transcriber = object.__new__(captions.VoskStreamingTranscriber)
        transcriber.committed_segments = []
        transcriber._append_committed_segment("yes")
        transcriber._append_committed_segment("yes")
        self.assertEqual(transcriber.committed_segments, ["yes", "yes"])

    def test_vosk_partial_does_not_strip_previous_utterance(self):
        transcriber = object.__new__(captions.VoskStreamingTranscriber)
        transcriber.committed_segments = ["yes"]
        transcriber.recent_audio = np.zeros(0, dtype=np.float32)
        transcriber.recognizer = Mock()
        transcriber.recognizer.AcceptWaveform.return_value = False
        transcriber.recognizer.PartialResult.return_value = '{"partial": "yes please"}'
        transcriber.feed(b"\0\0")
        self.assertEqual(transcriber.partial_text, "yes please")

    def test_partial_model_is_not_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "model.bin").touch()
            self.assertFalse(captions.model_is_complete(root))
            (root / "config.json").touch()
            (root / "tokenizer.json").touch()
            self.assertTrue(captions.model_is_complete(root))


class WhisperTests(unittest.TestCase):
    def make_transcriber(self):
        model = Mock()
        words = [SimpleNamespace(start=0, end=0.4, word="hello"),
                 SimpleNamespace(start=0.4, end=0.8, word="world")]
        model.transcribe.side_effect = lambda *args, **kwargs: (
            iter([SimpleNamespace(words=words)]), SimpleNamespace(language="en"),
        )
        return captions.StreamingTranscriber(model, "en", commit_ratio=0.6)

    def test_overlap_audio_does_not_recommit_words(self):
        transcriber = self.make_transcriber()
        transcriber.feed(np.ones(captions.SAMPLE_RATE, dtype=np.float32))
        transcriber.stabilize()
        transcriber.stabilize()
        self.assertEqual(transcriber.committed_words, ["hello"])
        transcriber.feed(np.ones(captions.SAMPLE_RATE // 2, dtype=np.float32))
        transcriber.stabilize()
        self.assertEqual(transcriber.committed_words, ["hello", "world"])
        self.assertAlmostEqual(transcriber.committed_audio_end, 0.45)

    def test_single_word_survives_silence(self):
        transcriber = self.make_transcriber()
        transcriber.feed(np.ones(100, dtype=np.float32))
        self.assertTrue(transcriber.commit_partial_phrase("yes"))
        self.assertEqual(transcriber.committed_words, ["yes"])
        self.assertEqual(len(transcriber.audio_buffer), 0)

    def test_silence_clears_already_committed_audio(self):
        transcriber = self.make_transcriber()
        transcriber.committed_words = ["hello", "world"]
        transcriber.feed(np.ones(100, dtype=np.float32))
        self.assertFalse(transcriber.commit_partial_phrase("hello world"))
        self.assertEqual(len(transcriber.audio_buffer), 0)
        self.assertEqual(transcriber.committed_words, ["hello", "world"])

    def test_transcript_is_bounded(self):
        transcriber = self.make_transcriber()
        transcriber._append_committed_words([str(i) for i in range(1000)])
        self.assertEqual(len(transcriber.committed_words), captions.MAX_COMMITTED_WORDS)
        self.assertEqual(transcriber.committed_words[-1], "999")

    def test_cpu_decode_failure_is_reported(self):
        transcriber = self.make_transcriber()
        transcriber.feed(np.ones(captions.SAMPLE_RATE, dtype=np.float32))
        transcriber.model.transcribe.side_effect = RuntimeError("broken decoder")
        with self.assertRaisesRegex(RuntimeError, "Speech decoding failed"):
            transcriber.fast_partial()


class TranslatorTests(unittest.TestCase):
    def test_inflight_request_is_not_queued_twice(self):
        started, release = threading.Event(), threading.Event()

        def translate(text, target, source, stop):
            started.set()
            release.wait(1)
            return "bonjour"

        with patch.object(captions, "translate_text", side_effect=translate) as translate_mock:
            translator = captions.AsyncTranslator()
            try:
                translator.request("hello", "fr", "en")
                self.assertTrue(started.wait(1))
                for _ in range(20):
                    translator.request("hello", "fr", "en")
                release.set()
                wait_for(lambda: translator.request("hello", "fr", "en") == "bonjour")
                self.assertEqual(translate_mock.call_count, 1)
            finally:
                release.set()
                translator.stop()

    def test_stable_and_live_requests_both_complete(self):
        with patch.object(captions, "translate_text", side_effect=lambda text, *_: "translated " + text):
            translator = captions.AsyncTranslator()
            try:
                with translator._lock:
                    translator._pending["stable"] = ("hello", "fr", "en")
                    translator._pending["live"] = ("hello everyone", "fr", "en")
                translator._wake_event.set()
                wait_for(lambda: len(translator._cache) == 2)
                self.assertEqual(translator.request("hello", "fr", "en", stream="stable"), "translated hello")
                self.assertEqual(translator.request("hello everyone", "fr", "en"), "translated hello everyone")
            finally:
                translator.stop()

    def test_transient_failure_is_retried(self):
        with patch.object(captions, "translate_text", side_effect=["", "bonjour"]) as translate_mock:
            translator = captions.AsyncTranslator()
            translator.RETRY_SECONDS = 0
            try:
                translator.request("hello", "fr", "en")
                wait_for(lambda: len(translator._retry_after) == 1)
                wait_for(lambda: translator.request("hello", "fr", "en") == "bonjour")
                self.assertEqual(translate_mock.call_count, 2)
            finally:
                translator.stop()

    def test_changed_sentence_cannot_reuse_old_translation(self):
        self.assertFalse(captions.AsyncTranslator._is_reusable_translation(
            "I am sure this is safe", "I am sure this is dangerous"))
        self.assertTrue(captions.AsyncTranslator._is_reusable_translation("Hello there", "Hello there everyone"))

    def test_cache_is_bounded_and_source_specific(self):
        with patch.object(captions, "translate_text", side_effect=lambda text, target, source, stop: source + text):
            translator = captions.AsyncTranslator()
            translator.CACHE_LIMIT = 3
            try:
                for index in range(6):
                    value = str(index)
                    wait_for(lambda: translator.request(value, "fr", "en") == "en" + value)
                self.assertEqual(len(translator._cache), 3)
                wait_for(lambda: translator.request("5", "fr", "de") == "de5")
            finally:
                translator.stop()

    def test_translation_uses_stdin_and_known_source_language(self):
        real_popen = subprocess.Popen
        commands = []

        def fake_trans(command, **kwargs):
            commands.append(command)
            # Reject anything the installed trans parser treats as a URL or option.
            script = "import sys; text=sys.stdin.read(); assert all(line.startswith(' ') for line in text.splitlines()); print(text.strip())"
            return real_popen([sys.executable, "-c", script], **kwargs)

        with patch.object(captions.subprocess, "Popen", side_effect=fake_trans):
            for value in ("-play a tune", "https://example.invalid", "http://example.invalid", "file:///private/example"):
                with self.subTest(value=value):
                    self.assertEqual(captions.translate_text(value, "fr", "en"), value)
        self.assertIn("en:fr", commands[0])
        self.assertIn("-no-browser", commands[0])
        self.assertNotIn("-play a tune", commands[0])

    def test_cancel_stops_translation_child(self):
        real_popen = subprocess.Popen
        children = []
        stop = threading.Event()

        def fake_trans(command, **kwargs):
            child = real_popen([sys.executable, "-c", "import time; time.sleep(30)"], **kwargs)
            children.append(child)
            stop.set()
            return child

        with patch.object(captions.subprocess, "Popen", side_effect=fake_trans):
            start = time.monotonic()
            self.assertEqual(captions.translate_text("hello", "fr", "en", stop), "")
            self.assertLess(time.monotonic() - start, 1)
        self.assertIsNotNone(children[0].poll())


class CaptureTests(unittest.TestCase):
    def test_stalled_capture_can_stop(self):
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"], stdout=subprocess.PIPE)
        capture = captions.AudioCaptureReader(child)
        try:
            self.assertEqual(capture.read(), b"")
            start = time.monotonic()
            capture.stop()
            self.assertLess(time.monotonic() - start, 1)
            self.assertIsNotNone(child.poll())
        finally:
            if child.poll() is None:
                capture.stop()

    def test_odd_pipe_reads_keep_complete_pcm_samples(self):
        script = "import os,time; os.write(1,b'\\x01'); time.sleep(.05); os.write(1,b'\\x02\\x03\\x04'); time.sleep(30)"
        child = subprocess.Popen([sys.executable, "-c", script], stdout=subprocess.PIPE)
        capture = captions.AudioCaptureReader(child)
        try:
            self.assertEqual(capture.read(), b"\x01\x02\x03\x04")
        finally:
            capture.stop()

    def test_capture_queue_is_bounded_to_recent_audio(self):
        child = subprocess.Popen([sys.executable, "-c", "import os,time; os.write(1,bytes(range(32))); time.sleep(30)"], stdout=subprocess.PIPE)
        with patch.object(captions.AudioCaptureReader, "MAX_BYTES", 8):
            capture = captions.AudioCaptureReader(child)
            try:
                self.assertEqual(capture.read(), bytes(range(24, 32)))
            finally:
                capture.stop()

    def test_speech_indicator_updates_without_text_change(self):
        with patch.object(sys, "argv", ["captions", "--state-file", "/unused", "--display-mode", "captions"]):
            args = captions.apply_preset(captions.parse_args())
        transcriber = Mock(source_language="en", runtime_device="vosk")
        transcriber.texts.return_value = ("hello", "hello", "")
        transcriber.speech_active.side_effect = [True, False]
        transcriber.committed_word_count.return_value = 1
        capture = Mock()
        reads = iter([b"\0\0", b"\0\0"])

        def read():
            chunk = next(reads, b"")
            if not chunk:
                captions.RUNNING = False
            return chunk

        capture.read.side_effect = read
        states = []
        with patch.object(captions, "ensure_vosk_model", return_value="/unused"), \
             patch.object(captions, "resolve_pulse_device", return_value="fake"), \
             patch.object(captions, "start_audio_capture"), \
             patch.object(captions, "AudioCaptureReader", return_value=capture), \
             patch.object(captions, "VoskStreamingTranscriber", return_value=transcriber), \
             patch.object(captions, "AsyncTranslator"), \
             patch.object(captions, "write_state", side_effect=lambda path, state: states.append(dict(state))):
            try:
                captions.RUNNING = True
                self.assertEqual(captions.run_streaming_asr_backend(args, Path("/unused"), captions.build_base_state(args)), 0)
            finally:
                captions.RUNNING = True
        active_states = [state["speech_active"] for state in states if state["current_text"] == "hello" and state["status"] == "running"]
        self.assertEqual(active_states, [True, False])


if __name__ == "__main__":
    unittest.main()
