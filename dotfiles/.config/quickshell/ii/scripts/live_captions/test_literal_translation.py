"""Offline literal-word tests with mocked model output and a synthetic local HTTP server."""
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
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
def local_server(body=b"{}", status=200, block_body=None, started=None, prefix_bytes=0):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def do_GET(self):
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if started:
                started.set()
            if prefix_bytes:
                self.wfile.write(body[:prefix_bytes])
                self.wfile.flush()
            if block_body:
                block_body.wait(2)
            try:
                self.wfile.write(body[prefix_bytes:])
            except (BrokenPipeError, ConnectionResetError):
                pass

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
    thread.start()
    try:
        with patch.object(literal, "OLLAMA_PORT", server.server_port), \
             patch.dict(os.environ, {"LIVE_TRANSLATION_OLLAMA_URL": f"http://127.0.0.1:{server.server_port}"}):
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


class StreamingGlossTests(unittest.TestCase):
    def test_validated_words_appear_before_full_response_with_original_inner_punctuation(self):
        source = "Er liest, das Buch."
        rows = gloss_rows(source, ["He", "reads", "the", "book"])
        snapshots = []

        def request(path, payload, *, on_content, **kwargs):
            self.assertTrue(payload["stream"])
            on_content('{"0":"He"')
            self.assertEqual(snapshots[-1], {"source": "Er", "translated": "He", "complete": False})
            on_content('{"0":"He","1":"reads","2":"the"')
            self.assertEqual(snapshots[-1]["source"], "Er liest, das")
            self.assertEqual(snapshots[-1]["translated"], "He reads, the")
            self.assertFalse(snapshots[-1]["complete"])
            return model_response(rows)

        cache = literal.LiteralCache()
        with patch.object(literal, "_installed_model", return_value="qwen-instruct:4b"), \
             patch.object(literal, "_request_json", side_effect=request):
            self.assertEqual(literal.translate_literal(source, "en", "de", on_progress=snapshots.append,
                                                      cache=cache), "He reads, the book.")
        self.assertEqual(snapshots[-1], {"source": source, "translated": "He reads, the book.", "complete": True})
        self.assertEqual(cache.snapshot(source, "en", "de"), snapshots[-1])

    def test_out_of_order_ids_wait_for_contiguous_source_prefix(self):
        source = "Er liest heute."
        snapshots = []

        def request(path, payload, *, on_content, **kwargs):
            on_content('{"2":"today"')
            self.assertEqual(snapshots, [])
            on_content('{"2":"today","0":"He"')
            self.assertEqual(snapshots[-1]["source"], "Er")
            on_content('{"2":"today","0":"He","1":"reads"}')
            self.assertEqual(snapshots[-1]["source"], "Er liest heute")
            self.assertFalse(snapshots[-1]["complete"])
            return model_response({"2": "today", "0": "He", "1": "reads"})

        with patch.object(literal, "_installed_model", return_value="qwen-instruct:4b"), \
             patch.object(literal, "_request_json", side_effect=request):
            literal.translate_literal(source, "en", "de", on_progress=snapshots.append)
        self.assertTrue(snapshots[-1]["complete"])

    def test_split_json_escapes_do_not_publish_partial_words(self):
        tokens = literal._source_tokens("coffee")
        self.assertEqual(literal._partial_glosses('{"0":"caf\\u00', tokens), {})
        self.assertEqual(literal._partial_glosses('{"0":"caf\\u00e9"', tokens), {0: "café"})
        with self.assertRaisesRegex(RuntimeError, "duplicate"):
            literal._partial_glosses('{"0":"café","0":"autre"}', tokens)
        with self.assertRaisesRegex(RuntimeError, "invalid"):
            literal._partial_glosses('{"1":"café"}', tokens)

    def test_invalid_final_response_retains_only_provisional_validated_prefix(self):
        source = "Er liest."
        cache, snapshots = literal.LiteralCache(), []

        def request(path, payload, *, on_content, **kwargs):
            on_content('{"0":"He"')
            return {"done": True, "message": {"content": '{"0":"He","0":"She","1":"reads"}'}}

        with patch.object(literal, "_installed_model", return_value="qwen-instruct:4b"), \
             patch.object(literal, "_request_json", side_effect=request), self.assertRaises(RuntimeError):
            literal.translate_literal(source, "en", "de", on_progress=snapshots.append, cache=cache)
        self.assertEqual(cache.snapshot(source, "en", "de"),
                         {"source": "Er", "translated": "He", "complete": False})
        self.assertTrue(all(not snapshot["complete"] for snapshot in snapshots))

    def test_append_only_growth_requests_only_tail_with_full_current_context(self):
        old = "I have read the old book"
        new = old + " today."
        cache, snapshots, requested = literal.LiteralCache(), [], []
        target_glosses = {"0": "Ich", "1": "habe", "2": "gelesen", "3": "das",
                          "4": "alte", "5": "Buch", "6": "heute"}

        def request(path, payload, *, on_content, **kwargs):
            data = json.loads(payload["messages"][1]["content"])
            requested.append(data)
            result = {key: target_glosses[key] for key in data["words"]}
            on_content(json.dumps(result))
            return model_response(result)

        with patch.object(literal, "_installed_model", return_value="qwen-instruct:4b"), \
             patch.object(literal, "_request_json", side_effect=request):
            literal.translate_literal(old, "de", "en", cache=cache)
            self.assertEqual(cache.snapshot(new, "de", "en"),
                             {"source": "I have read", "translated": "Ich habe gelesen", "complete": False})
            literal.translate_literal(new, "de", "en", cache=cache, on_progress=snapshots.append)
        self.assertEqual(snapshots[0]["source"], "I have read")
        self.assertEqual(set(requested[1]["words"]), {"3", "4", "5", "6"})
        self.assertEqual(requested[1]["context"], new)
        self.assertEqual(snapshots[-1]["translated"], "Ich habe gelesen das alte Buch heute.")
        self.assertTrue(snapshots[-1]["complete"])

    def test_old_inflight_prefix_is_available_while_live_source_keeps_growing(self):
        source = "I have already read the book and I will bring it tomorrow"
        cache, emitted, release = literal.LiteralCache(), threading.Event(), threading.Event()
        errors = []

        def request(path, payload, *, on_content, **kwargs):
            on_content('{"0":"Ich","1":"habe","2":"schon"')
            emitted.set()
            release.wait(1)
            data = json.loads(payload["messages"][1]["content"])
            return model_response({key: value for key, value in data["words"].items()})

        def translate():
            try:
                literal.translate_literal(source, "de", "en", cache=cache)
            except Exception as error:
                errors.append(error)

        with patch.object(literal, "_installed_model", return_value="qwen-instruct:4b"), \
             patch.object(literal, "_request_json", side_effect=request):
            thread = threading.Thread(target=translate)
            thread.start()
            try:
                self.assertTrue(emitted.wait(1))
                for addition in (" morning", " morning before", " morning before work"):
                    snapshot = cache.snapshot(source + addition, "de", "en")
                    self.assertEqual(snapshot["source"], "I have already")
                    self.assertFalse(snapshot["complete"])
                self.assertIsNone(cache.snapshot(source.replace("read", "written"), "de", "en"))
                self.assertIsNone(cache.snapshot(source, "fr", "en"))
            finally:
                release.set()
                thread.join(1)
        self.assertFalse(errors)

    def test_revised_tail_reuses_only_identical_leading_spans_with_context_margin(self):
        source = "I have already read the old book today"
        current = "I have already read the old book yesterday"
        cache = literal.LiteralCache()
        tokens = literal._source_tokens(source)
        cache._store(source, "de", "en", tokens,
                     {token["id"]: token["source"].upper() for token in tokens}, True)
        self.assertTrue(cache.can_reuse_source(source, current))
        self.assertEqual(cache.snapshot(current, "de", "en"),
                         {"source": "I have already read", "translated": "I HAVE ALREADY READ", "complete": False})
        for revised in ("You have already read the old book yesterday",
                        "I have:already read the old book yesterday"):
            self.assertFalse(cache.can_reuse_source(source, revised))
            self.assertIsNone(cache.snapshot(revised, "de", "en"))

    def test_reuse_guard_keeps_short_append_work_but_rejects_changed_or_partial_words(self):
        self.assertTrue(literal.LiteralCache.can_reuse_source("I read", "I read books"))
        self.assertTrue(literal.LiteralCache.can_reuse_source("I read", "I read"))
        self.assertFalse(literal.LiteralCache.can_reuse_source("a cat", "a caterpillar"))
        self.assertFalse(literal.LiteralCache.can_reuse_source("a cat", "a cat\u0301"))
        self.assertFalse(literal.LiteralCache.can_reuse_source("I read", "You read"))
        self.assertFalse(literal.LiteralCache.can_reuse_source("", "I read"))

    def test_changed_protected_suffix_does_not_become_a_completed_cache_hit(self):
        cache = literal.LiteralCache()
        for text, revised in (("word item 64", "word item 0"),
                              ("I read https://example.org", "I read https://example.net")):
            tokens = literal._source_tokens(text)
            cache._store(text, "de", "en", tokens,
                         {token["id"]: token["source"].upper() for token in tokens}, True)
            self.assertIsNone(cache.snapshot(revised, "de", "en"))

    def test_exact_and_punctuation_only_cache_hits_do_not_call_model(self):
        source = "Er liest das Buch"
        cache = literal.LiteralCache()
        with patch.object(literal, "_installed_model", return_value="qwen-instruct:4b"), \
             patch.object(literal, "_request_json", return_value=model_response(
                 gloss_rows(source, ["He", "reads", "the", "book"]))):
            literal.translate_literal(source, "en", "de", cache=cache)
        with patch.object(literal, "_installed_model") as model:
            self.assertEqual(literal.translate_literal(source, "en", "de", cache=cache), "He reads the book")
            self.assertEqual(literal.translate_literal(source + ".", "en", "de", cache=cache), "He reads the book.")
            model.assert_not_called()

    def test_callback_can_read_cache_without_lock_inversion(self):
        source = "Hallo"
        cache, snapshots = literal.LiteralCache(), []

        def callback(snapshot):
            snapshots.append(cache.snapshot(source, "en", "de"))

        with patch.object(literal, "_installed_model", return_value="qwen-instruct:4b"), \
             patch.object(literal, "_request_json", return_value=model_response({"0": "hello"})):
            thread = threading.Thread(target=lambda: literal.translate_literal(source, "en", "de",
                                                                               cache=cache, on_progress=callback))
            thread.start()
            thread.join(1)
        self.assertFalse(thread.is_alive())
        self.assertEqual(snapshots, [{"source": source, "translated": "hello", "complete": True}])

    def test_gloss_cache_is_bounded_and_does_not_cross_languages(self):
        cache = literal.LiteralCache()
        cache.LIMIT = 3
        for index in range(6):
            text = f"word item {index}"
            cache._store(text, "fr", "en", literal._source_tokens(text), {0: "mot", 1: "objet"}, True)
        self.assertEqual(len(cache._entries), 3)
        self.assertIsNone(cache.snapshot("word item 0", "fr", "en"))
        self.assertIsNone(cache.snapshot("word item 5", "de", "en"))
        self.assertIsNone(cache.snapshot("word item 5", "fr", "de"))

    def test_invalid_or_unsegmented_snapshot_is_unavailable_without_throwing(self):
        cache = literal.LiteralCache()
        self.assertIsNone(cache.snapshot("私はここにいる", "en", "ja"))
        self.assertEqual(cache.snapshot("42 https://example.org", "en"),
                         {"source": "42 https://example.org", "translated": "42 https://example.org", "complete": True})


class EndpointTests(unittest.TestCase):
    def test_dedicated_local_endpoint_accepts_loopback_addresses_only(self):
        for address, expected in (("http://127.0.0.1:11435", ("http", "127.0.0.1", 11435)),
                                  ("http://localhost:11435/", ("http", "localhost", 11435)),
                                  ("http://[::1]:11435", ("http", "::1", 11435))):
            with self.subTest(address=address), patch.dict(os.environ, {"LIVE_TRANSLATION_OLLAMA_URL": address}):
                self.assertEqual(literal._endpoint(), expected)
        for address in ("https://example.org", "http://192.168.1.4:11434", "http://user:secret@localhost:11434",
                        "http://localhost:11434/private", "file:///tmp/model", "http://localhost:11434?data=anything"):
            with self.subTest(address=address), patch.dict(os.environ, {"LIVE_TRANSLATION_OLLAMA_URL": address}), \
                 self.assertRaisesRegex(RuntimeError, "loopback"):
                literal._endpoint()


class HttpLifecycleTests(unittest.TestCase):
    def test_ndjson_stream_exposes_content_before_response_finishes(self):
        first = json.dumps({"message": {"content": '{"0":"Hello"'}, "done": False}).encode() + b"\n"
        last = json.dumps({"message": {"content": '}'}, "done": True, "done_reason": "stop"}).encode() + b"\n"
        emitted, release = threading.Event(), threading.Event()
        fragments, results = [], []

        def progress(content):
            fragments.append(content)
            emitted.set()

        def request():
            results.append(literal._request_json("/api/chat", timeout=1, on_content=progress))

        with local_server(first + last, block_body=release, prefix_bytes=len(first)):
            thread = threading.Thread(target=request)
            thread.start()
            try:
                self.assertTrue(emitted.wait(0.5))
                self.assertEqual(fragments, ['{"0":"Hello"'])
                self.assertTrue(thread.is_alive())
            finally:
                release.set()
                thread.join(1)
        self.assertFalse(thread.is_alive())
        self.assertEqual(results[0]["message"]["content"], '{"0":"Hello"}')
        self.assertTrue(results[0]["done"])

    def test_ndjson_stream_can_stop_after_an_early_word(self):
        first = json.dumps({"message": {"content": '{"0":"Hello"'}, "done": False}).encode() + b"\n"
        last = json.dumps({"message": {"content": '}'}, "done": True}).encode() + b"\n"
        emitted, release, stop = threading.Event(), threading.Event(), threading.Event()
        errors = []

        def request():
            try:
                literal._request_json("/api/chat", timeout=3, stop_event=stop,
                                      on_content=lambda _: emitted.set())
            except literal.LiteralTranslationCancelled:
                errors.append("cancelled")

        with local_server(first + last, block_body=release, prefix_bytes=len(first)):
            thread = threading.Thread(target=request)
            thread.start()
            self.assertTrue(emitted.wait(0.5))
            stop.set()
            thread.join(0.5)
            self.assertFalse(thread.is_alive())
            self.assertEqual(errors, ["cancelled"])

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
