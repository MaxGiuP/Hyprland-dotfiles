"""Offline literal-word tests with mocked model output and a synthetic local HTTP server."""
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading
import time
import unittest
from unittest.mock import patch

import literal_translation as literal


def model_response(rows):
    return {"done": True, "done_reason": "stop", "message": {"content": json.dumps(rows)}}


def gloss_rows(source, glosses):
    return {str(token["id"]): gloss for token, gloss in zip(literal._source_tokens(source), glosses)}


@contextmanager
def local_server(body=b"{}", status=200, block_body=None, started=None):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def do_GET(self):
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if started:
                started.set()
            if block_body:
                block_body.wait(2)
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
    thread.start()
    try:
        with patch.object(literal, "OLLAMA_PORT", server.server_port):
            yield
    finally:
        if block_body:
            block_body.set()
        server.shutdown()
        server.server_close()
        thread.join(1)


class LiteralGlossTests(unittest.TestCase):
    def translate_rows(self, source, rows, target="en", source_language="de"):
        with patch.object(literal, "_installed_model", return_value="qwen-instruct:4b"), \
             patch.object(literal, "_request_json", return_value=model_response(rows)):
            return literal.translate_literal(source, target, source_language)

    def test_per_word_glosses_mechanically_keep_original_german_verb_order(self):
        cases = [
            ("Er war gestern dort gegangen.", ["He", "was", "yesterday", "there", "gone"],
             "He was yesterday there gone."),
            ("Er hat gestern das Buch gelesen.", ["He", "has", "yesterday", "the", "book", "read"],
             "He has yesterday the book read."),
            ("Er war gestern dort gewesen.", ["He", "was", "yesterday", "there", "been"],
             "He was yesterday there been."),
        ]
        for source, glosses, expected in cases:
            with self.subTest(source=source):
                self.assertEqual(self.translate_rows(source, gloss_rows(source, glosses)), expected)

    def test_shuffled_response_rows_are_reassembled_by_source_id(self):
        source = "Er liest das Buch."
        rows = gloss_rows(source, ["He", "reads", "the", "book"])
        self.assertEqual(self.translate_rows(source, {key: rows[key] for key in ("3", "0", "2", "1")}), "He reads the book.")

    def test_same_source_word_can_have_different_glosses_based_on_full_context(self):
        cases = {"Die Bank ist bequem.": ["The", "bench", "is", "comfortable"],
                 "Die Bank verwaltet Geld.": ["The", "bank", "manages", "money"]}

        def request(path, payload, **kwargs):
            self.assertEqual(path, "/api/chat")
            data = json.loads(payload["messages"][1]["content"])
            source = data["context"]
            self.assertEqual(data["from"], "auto")
            self.assertEqual(data["to"], "English")
            self.assertEqual(set(payload["format"]["properties"]), set(data["words"]))
            self.assertFalse(payload["think"])
            self.assertFalse(payload["stream"])
            self.assertEqual(payload["options"]["temperature"], 0)
            return model_response(gloss_rows(source, cases[source]))

        with patch.object(literal, "_installed_model", return_value="qwen-instruct:4b"), \
             patch.object(literal, "_request_json", side_effect=request) as provider:
            self.assertEqual(literal.translate_literal("Die Bank ist bequem.", "en"), "The bench is comfortable.")
            self.assertEqual(literal.translate_literal("Die Bank verwaltet Geld.", "en"), "The bank manages money.")
            self.assertEqual(provider.call_count, 2)

    def test_original_punctuation_whitespace_numbers_and_urls_survive(self):
        source = '"Er",\twar gestern: dort gegangen!\n42 https://example.org/a,b?x=1.5'
        rows = gloss_rows(source, ["He", "was", "yesterday", "there", "gone"])
        self.assertEqual(self.translate_rows(source, rows),
                         '"He",\twas yesterday: there gone!\n42 https://example.org/a,b?x=1.5')

    def test_combining_marks_stay_with_hindi_arabic_and_decomposed_latin_words(self):
        for source, expected in [("मुझे पानी चाहिए", ["मुझे", "पानी", "चाहिए"]),
                                 ("أَنَا أَقْرَأُ", ["أَنَا", "أَقْرَأُ"]),
                                 ("Cafe\u0301 re\u0301sume\u0301", ["Cafe\u0301", "re\u0301sume\u0301"])]:
            with self.subTest(source=source):
                self.assertEqual([token["source"] for token in literal._source_tokens(source)], expected)
        source = "मुझे पानी चाहिए"
        self.assertEqual(self.translate_rows(source, gloss_rows(source, ["me", "water", "needed"]),
                                             source_language="hi"), "me water needed")

    def test_short_lexical_equivalents_and_all_supported_targets(self):
        self.assertEqual(self.translate_rows("zum Haus", gloss_rows("zum Haus", ["to the", "house"])),
                         "to the house")
        for target in literal._LANGUAGES:
            with self.subTest(target=target):
                source = "Hallo"
                rows = gloss_rows(source, ["词"])
                self.assertEqual(self.translate_rows(source, rows, target=target, source_language=""), "词")

    def test_identity_and_nonwords_do_not_call_provider(self):
        with patch.object(literal, "_request_json") as provider:
            self.assertEqual(literal.translate_literal("Already English.", "en", "en"), "Already English.")
            self.assertEqual(literal.translate_literal("42.5 https://example.org", "en", "de"),
                             "42.5 https://example.org")
            self.assertEqual(literal.translate_literal("", "en"), "")
            provider.assert_not_called()

    def test_missing_extra_duplicate_invalid_or_mismatched_ids_are_rejected(self):
        source = "Er liest."
        variants = [{"0": "He"}, {"0": "He", "1": "reads", "2": "extra"},
                    {"0": "He", "true": "reads"}, {"0": "He", "01": "reads"},
                    {"-1": "He", "1": "reads"}, {"0": "He", "1": {"gloss": "reads"}},
                    ["He", "reads"], {"tokens": ["He", "reads"]}]
        for rows in variants:
            with self.subTest(rows=rows), self.assertRaises(RuntimeError):
                self.translate_rows(source, rows)

    def test_fluent_paragraph_or_malformed_response_never_becomes_fallback(self):
        source = "Er liest."
        variants = ["He reads.", '"He reads."', "[]", '{"translation":"He reads."}',
                    '{"tokens":null}', '{"0":"He","0":"She","1":"reads"}',
                    '```json\n{"tokens": []}\n```']
        for content in variants:
            response = {"done": True, "message": {"content": content}}
            with self.subTest(content=content), \
                 patch.object(literal, "_installed_model", return_value="qwen-instruct:4b"), \
                 patch.object(literal, "_request_json", return_value=response), self.assertRaises(RuntimeError):
                literal.translate_literal(source, "en", "de")

    def test_empty_sentence_shaped_or_incomplete_glosses_are_rejected_atomically(self):
        for gloss in ("", " ", "He has already read the entire book", "He reads.", "word/alternative", "词。", "read (past)"):
            with self.subTest(gloss=gloss), self.assertRaises(RuntimeError):
                self.translate_rows("liest", gloss_rows("liest", [gloss]))
        with patch.object(literal, "_installed_model", return_value="qwen-instruct:4b"), \
             patch.object(literal, "_request_json", return_value={"done": False, "message": {"content": "{}"}}), \
             self.assertRaisesRegex(RuntimeError, "incomplete"):
            literal.translate_literal("Er liest.", "en", "de")

    def test_unsegmented_source_script_and_oversized_inputs_are_explicit_errors(self):
        with self.assertRaisesRegex(RuntimeError, "word-separated"):
            literal.translate_literal("私は昨日そこへ行った", "en", "ja")
        with self.assertRaisesRegex(RuntimeError, "too long"):
            literal.translate_literal("word " * (literal.MAX_SOURCE_WORDS + 1), "de", "en")


class ModelSelectionTests(unittest.TestCase):
    def setUp(self):
        literal._model_cache = None

    def tearDown(self):
        literal._model_cache = None

    def test_installed_four_billion_instruction_model_is_preferred_deterministically(self):
        models = [{"name": "qwen3.5:0.8b", "details": {"parameter_size": "0.8B"}},
                  {"name": "community/Qwen3-4B-Instruct:Q6_K", "details": {"parameter_size": "4.0B"}},
                  {"name": "qwen3-embedding:4b", "details": {"parameter_size": "4.0B"}},
                  {"name": "qwen3-instruct:30b", "details": {"parameter_size": "30.0B"}}]
        for order in (models, list(reversed(models))):
            self.assertEqual(literal._choose_model({"models": order}), "community/Qwen3-4B-Instruct:Q6_K")
        self.assertEqual(literal._choose_model({"models": models[:1]}), "qwen3.5:0.8b")
        for payload in ({"models": []}, {"models": "bad"}, {"models": [{"name": "embedding-only"}]},
                        {"models": [{"name": "qwen2.5:72b", "details": {"parameter_size": "unknown"}}]},
                        {"models": [{"name": "qwen3:32b", "details": {"parameter_size": None}}]}):
            with self.assertRaises(RuntimeError):
                literal._choose_model(payload)

    def test_model_discovery_is_shared_safely_between_threads(self):
        results = []

        def discover(*args, **kwargs):
            time.sleep(0.03)
            return {"models": [{"name": "qwen3-instruct:4b"}]}

        with patch.object(literal, "_request_json", side_effect=discover) as request:
            threads = [threading.Thread(target=lambda: results.append(literal._installed_model(None))) for _ in range(6)]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join(1)
            self.assertEqual(results, ["qwen3-instruct:4b"] * 6)
            self.assertEqual(request.call_count, 1)

    def test_waiting_for_model_discovery_can_be_cancelled(self):
        stop = threading.Event()
        errors = []

        def discover():
            try:
                literal._installed_model(stop)
            except literal.LiteralTranslationCancelled:
                errors.append("cancelled")

        with literal._model_lock:
            thread = threading.Thread(target=discover)
            thread.start()
            stop.set()
            thread.join(0.3)
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, ["cancelled"])


class HttpLifecycleTests(unittest.TestCase):
    def test_provider_errors_and_invalid_json_are_concise_errors(self):
        for body, status, expected in ((b"{}", 503, "HTTP 503"), (b"bad json", 200, "invalid JSON"),
                                       (b'{"error":"broken model"}', 200, "provider error")):
            with self.subTest(status=status, body=body), local_server(body, status), self.assertRaisesRegex(RuntimeError, expected):
                literal._request_json("/api/tags", timeout=1)

    def test_cancellation_interrupts_a_blocked_response_body(self):
        stop, release, started = threading.Event(), threading.Event(), threading.Event()
        errors = []

        def request():
            try:
                literal._request_json("/api/tags", timeout=5, stop_event=stop)
            except literal.LiteralTranslationCancelled:
                errors.append("cancelled")

        with local_server(b'{}', block_body=release, started=started):
            thread = threading.Thread(target=request)
            thread.start()
            self.assertTrue(started.wait(1))
            then = time.monotonic()
            stop.set()
            thread.join(0.5)
            self.assertFalse(thread.is_alive())
            self.assertLess(time.monotonic() - then, 0.5)
            self.assertEqual(errors, ["cancelled"])

    def test_timeout_is_bounded_and_preserves_no_partial_body(self):
        release = threading.Event()
        with local_server(b'{}', block_body=release):
            then = time.monotonic()
            with self.assertRaisesRegex(RuntimeError, "timed out"):
                literal._request_json("/api/tags", timeout=0.1)
            self.assertLess(time.monotonic() - then, 0.5)

    def test_oversized_responses_close_descriptors_even_when_tracebacks_are_retained(self):
        descriptors = Path("/proc/self/fd")
        if not descriptors.exists():
            self.skipTest("Linux descriptor count required")
        errors = []
        with local_server(b"x" * (literal.MAX_RESPONSE_BYTES + 100)):
            before = len(list(descriptors.iterdir()))
            for _ in range(5):
                try:
                    literal._request_json("/api/tags", timeout=1)
                except RuntimeError as error:
                    self.assertIn("oversized", str(error))
                    errors.append(error)
            self.assertEqual(len(errors), 5)
            self.assertLessEqual(len(list(descriptors.iterdir())), before + 1)

    def test_already_cancelled_request_does_not_open_connection(self):
        stop = threading.Event()
        stop.set()
        with patch.object(literal.http.client, "HTTPConnection") as connection, \
             self.assertRaises(literal.LiteralTranslationCancelled):
            literal.translate_literal("Hallo", "en", "de", stop)
        connection.assert_not_called()


if __name__ == "__main__":
    unittest.main()
