"""Offline source-boundary and identity tests; no translation services are used."""
import unittest

from translation_segments import MAX_SEGMENTS, SegmentTracker, split_source_segments


class PhraseBoundaryTests(unittest.TestCase):
    def test_comma_clauses_and_bare_conjunctions_keep_source_words_and_punctuation(self):
        self.assertEqual(split_source_segments(
            "I opened the settings panel, and I changed the font size."),
            ["I opened the settings panel,", "and I changed the font size."])
        self.assertEqual(split_source_segments(
            "I opened the settings panel and I changed the font size."),
            ["I opened the settings panel", "and I changed the font size."])

    def test_semicolon_colon_and_spaced_dash_form_natural_units(self):
        cases = {
            "I wanted a larger font; the text was hard to read.":
                ["I wanted a larger font;", "the text was hard to read."],
            "Our current plan for today: we will resize the panel.":
                ["Our current plan for today:", "we will resize the panel."],
            "The source text is visible — the translation is shown below.":
                ["The source text is visible —", "the translation is shown below."],
            "When you finish the report, send me a copy.":
                ["When you finish the report,", "send me a copy."],
        }
        for source, expected in cases.items():
            with self.subTest(source=source):
                self.assertEqual(split_source_segments(source), expected)

    def test_supported_language_conjunctions_require_an_actual_clause(self):
        cases = {
            "Ich öffne die neuen Einstellungen und ich ändere die Schriftgröße.":
                ["Ich öffne die neuen Einstellungen", "und ich ändere die Schriftgröße."],
            "Je regarde le texte original, mais je préfère la traduction.":
                ["Je regarde le texte original,", "mais je préfère la traduction."],
            "Io leggo il testo originale e io confronto la traduzione.":
                ["Io leggo il testo originale", "e io confronto la traduzione."],
            "Yo leo el texto original y yo cambio la traducción.":
                ["Yo leo el texto original", "y yo cambio la traducción."],
        }
        for source, expected in cases.items():
            with self.subTest(source=source):
                self.assertEqual(split_source_segments(source), expected)

    def test_noun_and_name_lists_embedded_in_a_clause_stay_together(self):
        for source in (
            "I bought fresh green apples, ripe yellow pears, and juicy oranges.",
            "I invited Alice Jane Smith, Robert William Jones, and Susan Brown.",
            "I invited Alice Jane Smith, Will James Smith, and Susan Brown.",
            "I bought a can of red paint, a can of blue paint, and a brush.",
            "I chose the large red hat, the small blue hat, and two scarves.",
            "I met my eldest son Jack, my youngest son Jim, and their friends.",
            "Ich kaufe frische grüne Äpfel, reife gelbe Birnen und rote Trauben.",
            "Je choisis des pommes vertes, des poires jaunes et des oranges.",
            "Io compro le mele verdi, le pere mature e le arance.",
            "Yo compro las manzanas verdes, las peras maduras y las naranjas.",
        ):
            with self.subTest(source=source):
                self.assertEqual(split_source_segments(source), [source])

    def test_list_stays_whole_before_following_actual_clause(self):
        self.assertEqual(split_source_segments(
            "I bought fresh green apples, ripe yellow pears, and I cooked a pie."),
            ["I bought fresh green apples, ripe yellow pears,", "and I cooked a pie."])

    def test_decimals_and_urls_keep_their_internal_punctuation(self):
        self.assertEqual(split_source_segments("I paid 1,500.50 euros, and I kept the receipt."),
                         ["I paid 1,500.50 euros,", "and I kept the receipt."])
        source = "I opened the page https://example.org/a,b?x=1.5 and I copied the address."
        self.assertEqual(split_source_segments(source),
                         ["I opened the page https://example.org/a,b?x=1.5", "and I copied the address."])
        source = "The following useful sites are listed: https://example.es/info and https://example.it/wiki."
        self.assertEqual(split_source_segments(source), [source])

    def test_indivisible_long_clauses_are_not_cut_at_word_counts(self):
        source = "The translation of this unusually long but indivisible descriptive expression is visible below."
        self.assertEqual(split_source_segments(source), [source])
        self.assertEqual(split_source_segments("I read and I learn."), ["I read and I learn."])

    def test_sentence_mode_remains_available(self):
        first = "I opened the settings panel, and I changed the font size."
        second = "The resulting text is larger."
        self.assertEqual(split_source_segments(first + " " + second, granularity="sentence"),
                         [first, second])
        self.assertEqual(SegmentTracker(granularity="sentence").update(first)[0]["source"], first)

    def test_boundaries_keep_titles_initials_and_cjk_sentences(self):
        self.assertEqual(split_source_segments("Dr. J. Smith paid 1.5 euros. 你好。再见！"),
                         ["Dr. J. Smith paid 1.5 euros.", "你好。", "再见！"])

    def test_unknown_granularity_fails_explicitly(self):
        with self.assertRaises(ValueError):
            split_source_segments("Hello", granularity="words")
        with self.assertRaises(ValueError):
            SegmentTracker(granularity="words")


class PhraseIdentityTests(unittest.TestCase):
    def test_separator_metadata_flows_phrases_inline_and_breaks_actual_sentences(self):
        source = ("I opened the settings panel, and I changed the font size. "
                  "The translated text is larger.\nAnother utterance follows")
        segments = SegmentTracker().update(source)
        self.assertEqual([item["separator"] for item in segments], ["", " ", "\n", "\n"])
        reconstructed = "".join(item["separator"] + item["source"] for item in segments)
        self.assertEqual(" ".join(reconstructed.split()), " ".join(source.split()))

    def test_tail_growth_keeps_ids_and_separators(self):
        tracker = SegmentTracker()
        old = tracker.update("I opened the settings panel, and I changed the font")
        new = tracker.update("I opened the settings panel, and I changed the font size.")
        self.assertEqual([item["id"] for item in old], [item["id"] for item in new])
        self.assertEqual([item["separator"] for item in new], ["", " "])

    def test_new_clause_boundary_preserves_existing_prefix_identity(self):
        tracker = SegmentTracker()
        old = tracker.update("I opened the settings panel, and I")
        new = tracker.update("I opened the settings panel, and I changed the font size")
        self.assertEqual(len(old), 1)
        self.assertEqual(len(new), 2)
        self.assertEqual(old[0]["id"], new[0]["id"])
        self.assertNotEqual(new[0]["id"], new[1]["id"])
        self.assertEqual(new[1]["separator"], " ")

    def test_sliding_window_reuses_identity_and_clears_first_visible_separator(self):
        tracker = SegmentTracker(limit=2)
        old = tracker.update("I opened the settings panel, and I changed the font size.")
        new = tracker.update("I opened the settings panel, and I changed the font size. Another sentence.")
        self.assertEqual(old[1]["id"], new[0]["id"])
        self.assertEqual([item["separator"] for item in new], ["", "\n"])

    def test_twelve_units_preserve_more_context_and_remain_bounded(self):
        self.assertEqual(MAX_SEGMENTS, 12)
        segments = SegmentTracker().update(" ".join(f"Sentence {index}." for index in range(20)))
        self.assertEqual(len(segments), 12)
        self.assertEqual(segments[0]["source"], "Sentence 8.")
        self.assertEqual(segments[0]["separator"], "")


if __name__ == "__main__":
    unittest.main()
