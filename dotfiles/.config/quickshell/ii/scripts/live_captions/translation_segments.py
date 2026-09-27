"""Source-based translation units shared by captions and screen OCR.

Translations must be requested for these exact source strings. Splitting an
independent translated paragraph by punctuation cannot establish correspondence.
"""
from __future__ import annotations

from difflib import SequenceMatcher
import re


MAX_SEGMENTS = 6
_BOUNDARY = re.compile(r"[.!?。！？]+[\"'’”»）)]*(?:\s+|$)|[。！？]+[\"'’”»）)]*|\n+")
_ABBREVIATIONS = {"mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "e.g", "i.e"}


def split_source_segments(text: str) -> list[str]:
    """Keep sentence punctuation and use ASR/OCR line breaks as phrase boundaries.

    Decimal points and common abbreviations stay inside their phrase. Languages
    without spaces can still split at their own sentence punctuation.
    """
    text = (text or "").strip()
    pieces = []
    start = 0
    for boundary in _BOUNDARY.finditer(text):
        punctuation = boundary.group()
        if punctuation.startswith(".") and not punctuation.startswith(".."):
            word = text[start:boundary.start()].rsplit(None, 1)[-1:] or [""]
            word = word[0].lower()
            if word in _ABBREVIATIONS or (len(word) == 1 and word.isalpha()):
                continue
        piece = " ".join(text[start:boundary.end()].split())
        if piece:
            pieces.append(piece)
        start = boundary.end()
    tail = " ".join(text[start:].split())
    if tail:
        pieces.append(tail)
    return pieces


class SegmentTracker:
    """Bound recent source units and retain identity across edits and scrolling."""

    def __init__(self, limit: int = MAX_SEGMENTS):
        self.limit = limit
        self._next_id = 0
        self._segments: list[dict] = []

    @staticmethod
    def _related(previous: str, current: str) -> bool:
        # Growing live tails and the clipped beginning of a rolling transcript
        # keep their colour. Translation reuse still requires an exact match.
        old, new = previous.casefold(), current.casefold()
        if old.startswith(new) or new.startswith(old) or old.endswith(new):
            return True
        previous_words, current_words = old.split(), new.split()
        overlap = 0
        for left, right in zip(previous_words, current_words):
            if left != right:
                break
            overlap += 1
        if overlap >= 2 and overlap >= min(len(previous_words), len(current_words)) / 2:
            return True
        # The rolling caption window can lose words at the front while gaining
        # them at the end during the same update.
        for size in range(min(len(previous_words), len(current_words)), 1, -1):
            if previous_words[-size:] == current_words[:size]:
                return True
        return False

    def update(self, text: str) -> list[dict]:
        sources = split_source_segments(text)[-self.limit:]
        previous = self._segments
        assigned: dict[int, str] = {}
        used: set[int] = set()
        matcher = SequenceMatcher(a=[item["source"] for item in previous], b=sources, autojunk=False)
        for block in matcher.get_matching_blocks():
            for offset in range(block.size):
                old_index, new_index = block.a + offset, block.b + offset
                assigned[new_index] = previous[old_index]["id"]
                used.add(old_index)
        for new_index, source in enumerate(sources):
            if new_index in assigned:
                continue
            for old_index, item in enumerate(previous):
                if old_index not in used and self._related(item["source"], source):
                    assigned[new_index] = item["id"]
                    used.add(old_index)
                    break
            if new_index not in assigned:
                self._next_id += 1
                assigned[new_index] = f"segment-{self._next_id}"
        self._segments = [{"id": assigned[index], "source": source}
                          for index, source in enumerate(sources)]
        return [dict(item) for item in self._segments]

    def reset(self) -> None:
        self._segments = []
