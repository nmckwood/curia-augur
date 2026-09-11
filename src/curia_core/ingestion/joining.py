"""Join election councils to deprivation Local Authority Districts by fuzzy name match.

Deterministic fuzzy string matching (user's decision - no Bedrock/semantic search).
Names are normalized (lower-case, strip punctuation and common suffix words) then matched
with rapidfuzz; a difflib fallback is used if rapidfuzz is unavailable locally.
Unmatched / ambiguous names are reported so the caller can write the unused log.
"""

import re
from rapidfuzz import fuzz

_STOPWORDS = {
    "council",
    "district",
    "borough",
    "county",
    "city",
    "metropolitan",
    "royal",
    "of",
    "the",
    "unitary",
    "authority",
    "ua",
}

MATCH_THRESHOLD = 90.0  # 0-100 similarity


def normalize_name(name):
    text = (name or "").lower()
    text = re.sub(r"[^a-z0-9\s]", " ", text)
    tokens = [t for t in text.split() if t and t not in _STOPWORDS]
    return " ".join(tokens)


def _score(a, b):
    return fuzz.token_sort_ratio(a, b)

def match_councils_to_lads(councils, lad_names, threshold=MATCH_THRESHOLD):
    """Match each council to its best LAD name above ``threshold``.

    Returns ``(matches, unmatched)`` where ``matches`` is ``{council: lad_name}`` and
    ``unmatched`` is a list of ``(council, best_lad, best_score)`` log tuples.
    """
    normalized_lads = {lad: normalize_name(lad) for lad in lad_names}
    matches = {}
    unmatched = []
    for council in councils:
        norm_council = normalize_name(council)
        best_lad = None
        best_score = -1.0
        for lad, norm_lad in normalized_lads.items():
            score = _score(norm_council, norm_lad)
            if score > best_score:
                best_score = score
                best_lad = lad
        if best_score >= threshold and best_lad is not None:
            matches[council] = best_lad
        else:
            unmatched.append((council, best_lad, round(best_score, 1)))
    return matches, unmatched
