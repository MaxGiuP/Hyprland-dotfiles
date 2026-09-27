"""Offline literal-mode routing, revisions, and visible-error regressions."""
import sys
from pathlib import Path
import threading
import time
import unittest
from unittest.mock import Mock, patch

import live_captions as captions
from translation_segments import SegmentTracker


def wait_for(predicate):
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.005)
    raise AssertionError('Literal worker did not finish')


class LiteralCaptionTests(unittest.TestCase):
    def test_style_cli_defaults_to_natural_and_is_recorded(self):
        args = ['captions', '--state-file', '/unused']
        with patch.object(sys, 'argv', args):
            self.assertEqual(captions.parse_args().translation_style, 'natural')
        with patch.object(sys, 'argv', args + ['--translation-style', 'literal']):
            parsed = captions.parse_args()
            self.assertEqual(captions.build_base_state(parsed)['translation_style'], 'literal')
        with self.assertRaises(ValueError):
            captions.AsyncTranslator('other')

    def test_literal_pairs_keep_gloss_order_and_existing_colour_identity(self):
        with patch.object(captions, 'translate_literal', return_value='He has yesterday the book read.') as literal, \
             patch.object(captions, 'translate_text') as natural:
            worker = captions.AsyncTranslator('literal')
            tracker = SegmentTracker()
            try:
                def snapshot():
                    return captions.paired_translations(worker, tracker,
                        'Er hat gestern das Buch gelesen.', '', 'en', 'de-DE')
                initial = snapshot()[3]
                wait_for(lambda: bool(snapshot()[0]))
                text, _, _, pairs = snapshot()
                self.assertEqual(text, 'He has yesterday the book read.')
                self.assertEqual(initial[0]['id'], pairs[0]['id'])
                self.assertFalse(pairs[0]['pending'])
                self.assertEqual(literal.call_args.args[:3], ('Er hat gestern das Buch gelesen.', 'en', 'de'))
                natural.assert_not_called()
            finally:
                worker.stop()

    def test_missing_model_is_visible_without_falling_back_to_natural(self):
        with patch.object(captions, 'translate_literal', side_effect=RuntimeError('Local literal model unavailable.')) as literal, \
             patch.object(captions, 'translate_text') as natural:
            worker = captions.AsyncTranslator('literal')
            try:
                worker.request('Er liest.', 'en', 'de')
                wait_for(lambda: bool(worker.error()))
                self.assertEqual(worker.error(), 'Local literal model unavailable.')
                self.assertEqual(worker.request('Er liest.', 'en', 'de'), '')
                self.assertEqual(literal.call_count, 1)
                natural.assert_not_called()
                worker.retain_streams(set())
                self.assertEqual(worker.error(), '')
            finally:
                worker.stop()

    def test_successful_retry_clears_error_and_retains_literal_style(self):
        with patch.object(captions, 'translate_literal', side_effect=[RuntimeError('Unavailable'), 'He reads.']):
            worker = captions.AsyncTranslator('literal')
            try:
                worker.request('Er liest.', 'en', 'de')
                wait_for(lambda: bool(worker.error()))
                with worker._lock:
                    worker._retry_after.clear()
                wait_for(lambda: worker.request('Er liest.', 'en', 'de') == 'He reads.')
                self.assertEqual(worker.error(), '')
            finally:
                worker.stop()

    def test_late_error_for_old_revision_does_not_poison_new_source(self):
        entered, release = threading.Event(), threading.Event()
        def translate(text, *_):
            if text == 'old':
                entered.set()
                release.wait(2)
                raise RuntimeError('Old error')
            return 'new gloss'
        with patch.object(captions, 'translate_literal', side_effect=translate):
            worker = captions.AsyncTranslator('literal')
            try:
                worker.request('old', 'en', 'de')
                self.assertTrue(entered.wait(1))
                worker.request('new', 'en', 'de')
                release.set()
                wait_for(lambda: worker.request('new', 'en', 'de') == 'new gloss')
                self.assertEqual(worker.error(), '')
            finally:
                release.set()
                worker.stop()

    def test_literal_mode_serializes_inference_and_cancels_promptly(self):
        entered = threading.Event()
        def translate(text, target, source, stop):
            entered.set()
            stop.wait(2)
            raise RuntimeError('Cancelled')
        with patch.object(captions, 'translate_literal', side_effect=translate) as literal:
            worker = captions.AsyncTranslator('literal')
            worker.request('one', 'en', 'de', stream='one')
            self.assertTrue(entered.wait(1))
            worker.request('two', 'en', 'de', stream='two')
            self.assertEqual(len(worker._threads), 1)
            started = time.monotonic()
            worker.stop()
            self.assertLess(time.monotonic() - started, 1)
            self.assertTrue(all(not thread.is_alive() for thread in worker._threads))
            self.assertEqual(literal.call_count, 1)
            self.assertEqual(worker.error(), '')

    def test_literal_mode_never_reuses_a_changed_prefix_result(self):
        entered, release = threading.Event(), threading.Event()
        def translate(text, *_):
            if text == 'Er hat gestern':
                entered.set()
                release.wait(2)
            return 'He has' if text == 'Er hat' else 'He has yesterday'
        with patch.object(captions, 'translate_literal', side_effect=translate):
            worker = captions.AsyncTranslator('literal')
            try:
                wait_for(lambda: worker.request('Er hat', 'en', 'de') == 'He has')
                self.assertEqual(worker.request('Er hat gestern', 'en', 'de'), '')
                self.assertTrue(entered.wait(1))
                self.assertEqual(worker.request('Er hat gestern', 'en', 'de'), '')
                release.set()
                wait_for(lambda: worker.request('Er hat gestern', 'en', 'de') == 'He has yesterday')
            finally:
                release.set()
                worker.stop()

    def test_live_loop_publishes_error_changes_without_new_source_words(self):
        with patch.object(sys, 'argv', ['captions', '--state-file', '/unused', '--translation-style', 'literal']):
            args = captions.apply_preset(captions.parse_args())
        transcriber = Mock(source_language='de', runtime_device='vosk')
        transcriber.texts.return_value = ('Er liest.', 'Er liest.', '')
        transcriber.speech_active.return_value = False
        transcriber.committed_word_count.return_value = 2
        translator = Mock()
        translator.error.side_effect = ['', 'Literal model unavailable.']
        capture = Mock()
        chunks = iter([b'xx', b'xx'])
        def read():
            chunk = next(chunks, b'')
            if not chunk:
                captions.RUNNING = False
            return chunk
        capture.read.side_effect = read
        states = []
        pairs = [{'id': 'segment-1', 'source': 'Er liest.', 'translated': '', 'pending': True}]
        with patch.object(captions, 'ensure_vosk_model', return_value='/unused'), \
             patch.object(captions, 'resolve_pulse_device', return_value='fake'), \
             patch.object(captions, 'start_audio_capture'), \
             patch.object(captions, 'AudioCaptureReader', return_value=capture), \
             patch.object(captions, 'VoskStreamingTranscriber', return_value=transcriber), \
             patch.object(captions, 'AsyncTranslator', return_value=translator), \
             patch.object(captions, 'paired_translations', return_value=('', '', '', pairs)), \
             patch.object(captions, 'write_state', side_effect=lambda path, state: states.append(dict(state))):
            try:
                captions.RUNNING = True
                self.assertEqual(captions.run_streaming_asr_backend(args, Path('/unused'), captions.build_base_state(args)), 0)
            finally:
                captions.RUNNING = True
        active = [state for state in states if state['current_text'] == 'Er liest.' and state['status'] == 'running']
        self.assertEqual([state['translation_error'] for state in active], ['', 'Literal model unavailable.'])
        self.assertEqual(active[-1]['message'], 'Literal model unavailable.')
        self.assertEqual(states[-1]['translation_error'], '')

    def test_natural_mode_uses_existing_provider_and_independent_cache(self):
        with patch.object(captions, 'translate_literal', return_value='He has yesterday read.') as literal, \
             patch.object(captions, 'translate_text', return_value='He read yesterday.') as natural:
            natural_worker, literal_worker = captions.AsyncTranslator(), captions.AsyncTranslator('literal')
            try:
                wait_for(lambda: natural_worker.request('Er hat gestern gelesen.', 'en', 'de') == 'He read yesterday.')
                wait_for(lambda: literal_worker.request('Er hat gestern gelesen.', 'en', 'de') == 'He has yesterday read.')
                self.assertEqual(natural.call_count, 1)
                self.assertEqual(literal.call_count, 1)
            finally:
                natural_worker.stop()
                literal_worker.stop()


if __name__ == '__main__':
    unittest.main()
