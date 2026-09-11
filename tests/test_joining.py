"""Tests for curia_core.ingestion.joining — fuzzy matching of election council names
to deprivation Local Authority District names."""

import pytest

from curia_core.ingestion import joining


# --- normalize_name ----------------------------------------------------------


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("Cambridgeshire County Council", "cambridgeshire"),
        ("Royal Borough of Kingston upon Thames", "kingston upon thames"),
        ("CITY OF YORK", "york"),
        ("St. Helens Metropolitan Borough", "st helens"),
        ("Herefordshire, County of", "herefordshire"),
        ("Bristol, City of", "bristol"),
    ],
)
def test_normalize_name_strips_punctuation_case_and_stopwords(raw, expected):
    assert joining.normalize_name(raw) == expected


@pytest.mark.parametrize("raw", [None, "", "   ", "Council District"])
def test_normalize_name_of_empty_or_all_stopword_input_is_empty(raw):
    assert joining.normalize_name(raw) == ""


def test_normalize_name_keeps_digits():
    assert joining.normalize_name("District 9 Council") == "9"


# --- match_councils_to_lads --------------------------------------------------


def test_exact_names_match():
    matches, unmatched = joining.match_councils_to_lads(
        ["Cambridgeshire"], ["Cambridgeshire", "Norfolk"]
    )
    assert matches == {"Cambridgeshire": "Cambridgeshire"}
    assert unmatched == []


def test_names_differing_only_by_suffix_words_match():
    """'Leeds City Council' and 'Leeds' are the same authority."""
    matches, unmatched = joining.match_councils_to_lads(
        ["Leeds City Council"], ["Leeds", "Bradford"]
    )
    assert matches == {"Leeds City Council": "Leeds"}
    assert unmatched == []


def test_reordered_tokens_match_via_token_sort():
    matches, _ = joining.match_councils_to_lads(
        ["Herefordshire, County of"], ["County of Herefordshire", "Shropshire"]
    )
    assert matches == {"Herefordshire, County of": "County of Herefordshire"}


def test_a_name_with_no_plausible_counterpart_is_reported_unmatched():
    matches, unmatched = joining.match_councils_to_lads(
        ["Totally Fictional Place"], ["Cambridgeshire", "Norfolk"]
    )

    assert matches == {}
    assert len(unmatched) == 1
    council, best_lad, score = unmatched[0]
    assert council == "Totally Fictional Place"
    assert best_lad in {"Cambridgeshire", "Norfolk"}  # the closest, still too far
    assert score < joining.MATCH_THRESHOLD


def test_unmatched_scores_are_rounded_for_the_log():
    _, unmatched = joining.match_councils_to_lads(["Zxqv"], ["Cambridgeshire"])
    score = unmatched[0][2]
    assert score == round(score, 1)


def test_threshold_is_configurable():
    """Lowering the bar lets a weak match through; that is the knob operators have."""
    councils, lads = ["Northshire"], ["Southshire"]

    strict, _ = joining.match_councils_to_lads(councils, lads, threshold=95)
    loose, loose_unmatched = joining.match_councils_to_lads(councils, lads, threshold=10)

    assert strict == {}
    assert loose == {"Northshire": "Southshire"}
    assert loose_unmatched == []


def test_an_empty_lad_list_leaves_everything_unmatched_with_no_best_candidate():
    matches, unmatched = joining.match_councils_to_lads(["Anytown"], [])
    assert matches == {}
    assert unmatched == [("Anytown", None, -1.0)]


def test_no_councils_produces_no_matches_and_no_log_lines():
    assert joining.match_councils_to_lads([], ["Norfolk"]) == ({}, [])


def test_two_councils_may_map_to_the_same_lad():
    """The joiner picks the best LAD per council independently; the pipeline is
    responsible for what it does with a collision."""
    matches, _ = joining.match_councils_to_lads(
        ["Norfolk County Council", "Norfolk Council"], ["Norfolk"]
    )
    assert matches == {
        "Norfolk County Council": "Norfolk",
        "Norfolk Council": "Norfolk",
    }