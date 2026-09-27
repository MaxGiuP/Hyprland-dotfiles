"""Synthetic audio/model checks for speech flushed at the end of an utterance."""

from copy import deepcopy
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import numpy as np

import live_captions as captions


WORDS = ["first", "middle", "remaining", "words", "fifth", "sixth"]


def decode_result(words, offset=0):
    timestamps = [SimpleNamespace(start=index * 0.4 - offset, end=(index + 1) * 0.4 - offset, word=word)
                  for index, word in enumerate(words) if (index + 1) * 0.4 > offset]
    return iter([SimpleNamespace(words=timestamps)]), SimpleNamespace(language="en")


def speech_then_silence(speech=2.4, silence=0.8):
    return np.concatenate([np.full(round(speech * captions.SAMPLE_RATE), 0.5, dtype=np.float32),
                           np.zeros(round(silence * captions.SAMPLE_RATE), dtype=np.float32)])


class WhisperFinalizationTests(unittest.TestCase):
    def make_transcriber(self, model, **settings):
        return captions.StreamingTranscriber(model, "en", min_buffer_seconds=0.09,
                                            fast_window_seconds=1.05, **settings)

    def test_final_pass_preserves_middle_words_missing_from_the_short_partial(self):
        model = Mock()
        model.transcribe.side_effect = lambda *args, **kwargs: decode_result(WORDS)
        transcriber = self.make_transcriber(model, commit_ratio=0.24)
        transcriber.feed(speech_then_silence())
        transcriber.stabilize()
        self.assertEqual(transcriber.committed_words, ["first"])

        transcriber.finalize_phrase("fifth sixth")

        self.assertEqual(transcriber.committed_words, WORDS)
        self.assertEqual(model.transcribe.call_count, 2)
        self.assertTrue(model.transcribe.call_args.kwargs["word_timestamps"])
        self.assertEqual(len(model.transcribe.call_args.args[0]), round(3.2 * captions.SAMPLE_RATE))
        self.assertEqual(len(transcriber.audio_buffer), 0)
        self.assertEqual(transcriber.committed_audio_end, 0)

    def test_final_pass_respects_timestamp_origin_after_periodic_audio_trimming(self):
        original = speech_then_silence()
        model = Mock()

        def decode(audio, **kwargs):
            offset = (len(original) - len(audio)) / captions.SAMPLE_RATE
            return decode_result(WORDS, offset)

        model.transcribe.side_effect = decode
        transcriber = self.make_transcriber(model, commit_ratio=0.6)
        transcriber.feed(original)
        transcriber.stabilize()
        self.assertEqual(transcriber.committed_words, WORDS[:4])
        self.assertLess(len(transcriber.audio_buffer), len(original))
        transcriber.finalize_phrase("fifth sixth")
        self.assertEqual(transcriber.committed_words, WORDS)

    def test_empty_final_decode_can_retain_a_short_recognized_word_once(self):
        model = Mock()
        model.transcribe.side_effect = lambda *args, **kwargs: decode_result([])
        transcriber = self.make_transcriber(model)
        transcriber.feed(speech_then_silence(speech=0.4))
        transcriber.finalize_phrase("hello")
        transcriber.finalize_phrase("hello")
        self.assertEqual(transcriber.committed_words, ["hello"])
        self.assertEqual(model.transcribe.call_count, 1)

    def test_partial_fallback_strips_previously_committed_overlap(self):
        model = Mock()
        model.transcribe.side_effect = lambda *args, **kwargs: decode_result([])
        transcriber = self.make_transcriber(model)
        transcriber.committed_words = ["hello"]
        transcriber.committed_audio_end = 0.4
        transcriber.feed(speech_then_silence(speech=0.8))
        transcriber.finalize_phrase("hello world")
        self.assertEqual(transcriber.committed_words, ["hello", "world"])

    def test_silent_tail_cannot_add_decoder_hallucinations_or_stale_partial(self):
        model = Mock()
        model.transcribe.side_effect = lambda *args, **kwargs: decode_result(["hello", "phantom", "words"])
        transcriber = self.make_transcriber(model)
        transcriber.committed_words = ["hello"]
        transcriber.committed_audio_end = 0.4
        transcriber.feed(speech_then_silence(speech=0.4, silence=1.0))
        transcriber.finalize_phrase("hello phantom words")
        self.assertEqual(transcriber.committed_words, ["hello"])

    def test_pure_silence_is_not_decoded_or_committed(self):
        model = Mock()
        transcriber = self.make_transcriber(model)
        transcriber.feed(speech_then_silence(speech=0, silence=1.0))
        transcriber.finalize_phrase("stale words")
        model.transcribe.assert_not_called()
        self.assertEqual(transcriber.committed_words, [])
        self.assertEqual(len(transcriber.audio_buffer), 0)

    def test_cuda_finalization_error_preserves_audio_for_cpu_retry(self):
        failed = Mock()
        failed.transcribe.side_effect = RuntimeError("CUDA failed during final decode")
        transcriber = self.make_transcriber(failed)
        transcriber.runtime_device = "cuda"
        transcriber.feed(speech_then_silence())
        original = transcriber.audio_buffer.copy()
        with self.assertRaises(captions.CaptionRuntimeFallback):
            transcriber.finalize_phrase("fifth sixth")
        np.testing.assert_array_equal(transcriber.audio_buffer, original)
        self.assertEqual(transcriber.committed_words, [])
        cpu_model = Mock()
        cpu_model.transcribe.side_effect = lambda *args, **kwargs: decode_result(WORDS)
        transcriber.model = cpu_model
        transcriber.runtime_device = "cpu"
        transcriber.finalize_phrase("fifth sixth")
        self.assertEqual(transcriber.committed_words, WORDS)

    def run_synthetic_capture_loop(self, fail_final_cuda=False):
        clock = [0.0]
        model = Mock()
        cpu_model = Mock()
        timestamp_calls = [0]

        def decode(audio, **kwargs):
            if not kwargs["word_timestamps"]:
                return iter([SimpleNamespace(text="fifth sixth")]), SimpleNamespace(language="en")
            timestamp_calls[0] += 1
            if fail_final_cuda and timestamp_calls[0] == 3:
                raise RuntimeError("CUDA failed during final decode")
            return decode_result(WORDS)

        model.transcribe.side_effect = decode
        cpu_model.transcribe.side_effect = lambda *args, **kwargs: decode_result(WORDS)
        chunks = iter([
            (2.4, np.full(round(2.4 * captions.SAMPLE_RATE), 16000, dtype=np.int16).tobytes()),
            (3.3, np.zeros(round(0.9 * captions.SAMPLE_RATE), dtype=np.int16).tobytes()),
        ])
        capture = Mock()

        def read():
            item = next(chunks, None)
            if item is None:
                captions.RUNNING = False
                return b""
            clock[0], data = item
            return data

        capture.read.side_effect = read
        states = []
        runtime = "cuda" if fail_final_cuda else "cpu"
        with patch.object(sys, "argv", ["captions", "--state-file", "/unused", "--display-mode", "captions", "--language", "en"]), \
             patch.object(captions, "load_model", side_effect=[(model, runtime), (cpu_model, "cpu")]) as load, \
             patch.object(captions, "resolve_pulse_device", return_value="synthetic"), \
             patch.object(captions, "start_audio_capture"), \
             patch.object(captions, "AudioCaptureReader", return_value=capture), \
             patch.object(captions, "AsyncTranslator"), \
             patch.object(captions.time, "monotonic", side_effect=lambda: clock[0]), \
             patch.object(captions.time, "sleep"), \
             patch.object(captions, "write_state", side_effect=lambda path, state: states.append(deepcopy(state))):
            try:
                captions.RUNNING = True
                self.assertEqual(captions.main(), 0)
            finally:
                captions.RUNNING = True
        final_speech = [state for state in states if state["status"] == "running"
                        and state.get("speech_active") is False]
        self.assertTrue(final_speech)
        self.assertEqual(final_speech[-1]["current_text"], " ".join(WORDS))
        self.assertEqual(final_speech[-1]["runtime_device"], "cpu")
        capture.stop.assert_called_once()
        if fail_final_cuda:
            self.assertEqual(load.call_args.kwargs, {"force_device": "cpu"})
            self.assertEqual(cpu_model.transcribe.call_count, 1)

    def test_main_loop_flushes_whole_utterance_when_silence_closes_phrase(self):
        self.run_synthetic_capture_loop()

    def test_main_loop_retries_final_decode_after_cuda_failure(self):
        self.run_synthetic_capture_loop(fail_final_cuda=True)


if __name__ == "__main__":
    unittest.main()
