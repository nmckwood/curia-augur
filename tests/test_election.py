"""Tests for curia_core.ingestion.election — seat counting, the majority-flip
change_factor, and the dropping of councils with no successor."""

from curia_core.ingestion import election
from tests.conftest import councillor_rows


def test_seat_counts_tallies_one_row_per_councillor():
    rows = councillor_rows({"Anytown": {"Labour": 3, "Conservative": 2}})
    assert election.seat_counts(rows) == {
        "Anytown": {"Labour": 3, "Conservative": 2}
    }


def test_seat_counts_trims_whitespace_and_skips_incomplete_rows():
    rows = [
        {"Council": "  Anytown  ", "Party Name": " Labour "},
        {"Council": "", "Party Name": "Labour"},          # no council
        {"Council": "Anytown", "Party Name": ""},          # no party
        {"Council": "Anytown"},                            # missing key entirely
        {"Council": "Anytown", "Party Name": None},        # null party
    ]
    assert election.seat_counts(rows) == {"Anytown": {"Labour": 1}}


def test_seat_counts_of_no_rows_is_empty():
    assert election.seat_counts([]) == {}


def test_change_factor_is_one_when_the_majority_party_flips():
    benchmark = councillor_rows({"Anytown": {"Labour": 3, "Conservative": 2}})
    target = councillor_rows({"Anytown": {"Conservative": 3, "Labour": 2}})

    results, absent = election.build_election_results(benchmark, target)

    assert absent == []
    assert results["Anytown"]["change_factor"] == 1
    assert results["Anytown"]["Conservative"] == 1   # 3 - 2
    assert results["Anytown"]["Labour"] == -1        # 2 - 3
    assert results["Anytown"]["council"] == "Anytown"


def test_change_factor_is_zero_when_the_majority_party_holds():
    """Seats can move a long way without the largest party changing."""
    benchmark = councillor_rows({"Steadytown": {"Labour": 10, "Conservative": 1}})
    target = councillor_rows({"Steadytown": {"Labour": 6, "Conservative": 5}})

    results, _ = election.build_election_results(benchmark, target)

    assert results["Steadytown"]["change_factor"] == 0
    assert results["Steadytown"]["Labour"] == -4


def test_a_party_present_in_only_one_year_gets_a_signed_delta():
    benchmark = councillor_rows({"Anytown": {"Labour": 3}})
    target = councillor_rows({"Anytown": {"Labour": 3, "Green": 2}})

    results, _ = election.build_election_results(benchmark, target)

    assert results["Anytown"]["Green"] == 2
    assert results["Anytown"]["change_factor"] == 0


def test_ties_are_broken_by_party_name_so_results_are_deterministic():
    """A tie must not make change_factor depend on dict ordering."""
    benchmark = councillor_rows({"Tietown": {"Labour": 2, "Conservative": 2}})
    target = councillor_rows({"Tietown": {"Conservative": 2, "Labour": 2}})

    first, _ = election.build_election_results(benchmark, target)
    second, _ = election.build_election_results(benchmark, target)

    assert first["Tietown"]["change_factor"] == second["Tietown"]["change_factor"] == 0


def test_councils_absent_from_the_target_year_are_dropped_and_reported():
    """Abolished/reorganised councils have no successor, so scoring them as
    'did not change' would dilute the positive class."""
    benchmark = councillor_rows(
        {"Abolishedshire": {"Labour": 2}, "Survivortown": {"Labour": 2}}
    )
    target = councillor_rows({"Survivortown": {"Labour": 2}})

    results, absent = election.build_election_results(benchmark, target)

    assert absent == ["Abolishedshire"]
    assert "Abolishedshire" not in results
    assert "Survivortown" in results


def test_absent_councils_are_sorted():
    benchmark = councillor_rows(
        {"Zed": {"Lab": 1}, "Alpha": {"Lab": 1}, "Mid": {"Lab": 1}}
    )
    _, absent = election.build_election_results(benchmark, [])
    assert absent == ["Alpha", "Mid", "Zed"]


def test_councils_new_in_the_target_year_are_simply_not_scored():
    """There is no benchmark to compare a brand-new council against."""
    benchmark = councillor_rows({"Old": {"Labour": 2}})
    target = councillor_rows({"Old": {"Labour": 2}, "BrandNew": {"Green": 3}})

    results, absent = election.build_election_results(benchmark, target)

    assert set(results) == {"Old"}
    assert absent == []


def test_every_change_factor_is_binary():
    benchmark = councillor_rows(
        {"A": {"Lab": 3, "Con": 1}, "B": {"Con": 4}, "C": {"LD": 2, "Lab": 1}}
    )
    target = councillor_rows(
        {"A": {"Lab": 2, "Con": 3}, "B": {"Con": 2}, "C": {"LD": 5, "Lab": 4}}
    )

    results, _ = election.build_election_results(benchmark, target)

    assert {r["change_factor"] for r in results.values()} <= {0, 1}
    assert results["A"]["change_factor"] == 1
    assert results["B"]["change_factor"] == 0
    assert results["C"]["change_factor"] == 0
