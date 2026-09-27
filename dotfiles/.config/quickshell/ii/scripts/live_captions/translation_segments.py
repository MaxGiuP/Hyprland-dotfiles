"""Source-based translation units shared by captions and screen OCR.

Translations must be requested for these exact source strings. Splitting an
independent translated paragraph by punctuation cannot establish correspondence.
"""
from __future__ import annotations

from difflib import SequenceMatcher
import re


MAX_SEGMENTS = 12
_BOUNDARY = re.compile(r"[.!?。！？]+[\"'’”»）)]*(?:\s+|$)|[。！？]+[\"'’”»）)]*|\n+")
_ABBREVIATIONS = {"mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "e.g", "i.e"}


# These are only hints for finding an actual clause, not language detection or
# word alignment. Requiring clause evidence on both sides avoids colouring each
# item of a list as if it were an independently translated sentence.
_CONJUNCTIONS = {
    "and", "but", "or", "yet", "so", "und", "aber", "oder", "denn",
    "et", "mais", "ou", "donc", "car", "e", "ma", "o", "quindi", "però",
    "y", "pero", "sino",
}
_SUBJECTS = {
    "i", "you", "he", "she", "it", "we", "they",
    "ich", "du", "er", "sie", "es", "wir", "ihr",
    "je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
    "io", "lui", "lei", "noi", "voi", "loro",
    "yo", "tú", "él", "ella", "nosotros", "nosotras", "vosotros", "vosotras",
    "ellos", "ellas", "usted", "ustedes",
}
_FINITE_VERBS = {
    "am", "is", "are", "was", "were", "has", "have", "had", "can", "could",
    "will", "would", "shall", "should", "must", "does", "did",
    "bin", "bist", "ist", "sind", "seid", "war", "waren", "wird", "werden",
    "wurde", "wurden", "habe", "hast", "hat", "haben", "habt", "kann", "kannst",
    "können", "muss", "müssen", "soll", "sollen", "möchte", "möchten",
    "suis", "est", "sommes", "êtes", "sont", "étais", "était", "étaient",
    "avons", "avez", "ont", "peux", "peut", "pouvons", "pouvez", "peuvent",
    "dois", "doit", "devons", "devez", "doivent",
    "sono", "sei", "siamo", "siete", "ero", "era", "erano", "ho", "hai", "ha",
    "abbiamo", "avete", "hanno", "posso", "puoi", "può", "possiamo", "potete",
    "possono", "devo", "devi", "deve", "dobbiamo", "dovete", "devono",
    "soy", "eres", "es", "somos", "sois", "son", "estoy", "estás", "está",
    "estamos", "estáis", "están", "estaba", "estaban", "tengo", "tienes",
    "tiene", "tenemos", "tienen", "puedo", "puedes", "puede", "podemos", "pueden",
}
# A few common imperatives / subjects omitted in Italian and Spanish. Unknown
# verbs stay in a longer phrase instead of risking an arbitrary noun-list split.
_VERB_STARTS = {
    "open", "close", "change", "resize", "translate", "choose", "select", "keep",
    "send", "restart", "start", "stop", "adjust", "click", "press", "check",
    "aggiungi", "apri", "chiudi", "cambia", "scegli", "invia", "voglio", "penso",
    "credo", "apro", "vedo", "capisco", "cambio", "leggo", "preferisco",
    "abre", "cierra", "cambia", "elige", "envía", "quiero", "necesito", "creo",
    "pienso", "abro", "abrí", "cambié", "cambio", "veo", "entiendo", "encendí",
}
_NON_VERB_AFTER_SUBJECT = {
    "and", "or", "und", "oder", "et", "ou", "e", "o", "y",
    "in", "on", "at", "of", "with", "from", "to", "for", "the", "a", "an",
    "mit", "bei", "von", "zu", "im", "am", "dans", "avec", "de", "du",
    "des", "con", "en", "del", "della", "di",
}
_WORD = re.compile(r"[^\W\d_]+(?:['’][^\W\d_]+)*", re.UNICODE)
_URL = re.compile(r"(?:[a-z][a-z0-9+.-]*://|www\.)\S+", re.IGNORECASE)
# These verb forms are also ordinary nouns/names in another supported language
# (an English hat/bin/son, or Will Smith). Require a subject for those cases.
_AMBIGUOUS_VERBS = {"can", "will", "bin", "hat", "war", "son", "ha", "ho"}
_CONJUNCTION_PATTERN = r"\b(?:" + "|".join(sorted(_CONJUNCTIONS, key=len, reverse=True)) + r")\b"
_CLAUSE_BOUNDARY = re.compile(
    r"(?P<punct>[,;:]\s+|\s+[—–-]\s+)|(?P<conjunction>(?<=\s)"
    + _CONJUNCTION_PATTERN + r"(?=\s))", re.IGNORECASE,
)


def _sentence_segments(text: str) -> list[str]:
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


def _clause_evidence(text: str, *, leading: bool = False) -> bool:
    text = _URL.sub("link", text)
    words = _WORD.findall(text)
    while words and words[0].casefold() in _CONJUNCTIONS:
        words.pop(0)
    if not words:
        return False
    if leading:
        # Do not let a later clause make an earlier noun-list item look like a
        # clause. E.g. "green pears, and I cooked a pie" starts with a list item.
        first_word = text.find(words[0])
        lead = text[first_word:]
        boundary = _CLAUSE_BOUNDARY.search(lead)
        if boundary:
            words = _WORD.findall(lead[:boundary.start()])
    lower = [word.casefold() for word in words]
    if any(word in _FINITE_VERBS and word not in _AMBIGUOUS_VERBS for word in lower):
        return True
    if lower and lower[0] in _VERB_STARTS:
        return True
    for index, word in enumerate(lower[:3]):
        # Contractions such as "I'm", "j'ai", "c'est" contain the predicate.
        if re.match(r"(?:i|you|he|she|it|we|they)['’](?:m|re|s|ve|ll|d)$", word):
            return True
        if word.startswith(("j'", "j’", "c'est", "c’est")):
            return True
        if (word in _SUBJECTS and index + 2 < len(lower)
                and lower[index + 1] not in _NON_VERB_AFTER_SUBJECT):
            return True
    # Proper-name subjects followed by a regular past-tense verb are common,
    # but capitalized names without a verb (Alice Smith, Bob Jones) stay whole.
    return (len(words) >= 3 and words[0][0].isupper()
            and not lower[0].endswith("ly")
            and len(lower[1]) >= 5 and lower[1].endswith("ed"))


def _word_count(text: str) -> int:
    # Numbers and URLs count as one word each; their internal punctuation does
    # not make a three-word phrase look long enough to split.
    return sum(any(character.isalnum() for character in word) for word in text.split())


def _phrase_segments(sentence: str) -> list[str]:
    pieces = []
    start = 0
    for boundary in _CLAUSE_BOUNDARY.finditer(sentence):
        end = boundary.end() if boundary.group("punct") else boundary.start()
        left, right = sentence[start:end].strip(), sentence[end:].strip()
        # Keep very short expressions and indivisible clauses together. There
        # is deliberately no fixed word-position cut when a phrase is long.
        if _word_count(left) < 4 or _word_count(right) < 3:
            continue
        strong_punctuation = boundary.group("punct") and any(
            character in boundary.group("punct") for character in ";:—–-"
        )
        if not (_clause_evidence(left) or strong_punctuation):
            continue
        if not _clause_evidence(right, leading=True):
            continue
        pieces.append(left)
        start = end
    tail = sentence[start:].strip()
    if tail:
        pieces.append(tail)
    return pieces


def _source_units(text: str, granularity: str) -> list[dict]:
    if granularity not in {"sentence", "phrase"}:
        raise ValueError("Translation granularity must be 'sentence' or 'phrase'.")
    units = []
    for sentence in _sentence_segments(text):
        pieces = _phrase_segments(sentence) if granularity == "phrase" else [sentence]
        for index, source in enumerate(pieces):
            units.append({"source": source, "separator": (" " if index else "\n") if units else ""})
    return units


def split_source_segments(text: str, granularity: str = "phrase") -> list[str]:
    """Return source phrases, or full sentences in optional sentence mode.

    Phrase mode uses clause punctuation and conjunctions conservatively. Source
    units are translated independently; target-language word order never decides
    where colours go. Decimal points, names/lists and URL tokens stay intact.
    """
    return [item["source"] for item in _source_units(text, granularity)]


class SegmentTracker:
    """Bound recent source units and retain identity across edits and scrolling."""

    def __init__(self, limit: int = MAX_SEGMENTS, granularity: str = "phrase"):
        if granularity not in {"sentence", "phrase"}:
            raise ValueError("Translation granularity must be 'sentence' or 'phrase'.")
        self.limit = limit
        self.granularity = granularity
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
        units = _source_units(text, self.granularity)[-self.limit:]
        if units:
            units[0]["separator"] = ""
        sources = [item["source"] for item in units]
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
        self._segments = [{"id": assigned[index], **unit}
                          for index, unit in enumerate(units)]
        return [dict(item) for item in self._segments]

    def reset(self) -> None:
        self._segments = []
