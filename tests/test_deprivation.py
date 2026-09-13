"""Tests for curia_core.ingestion.deprivation — LSOA-to-LAD aggregation, the
rank-to-percentile rebasing, and cross-edition deltas."""

import pytest

from curia_core.common.schemas import DOMAINS, decile_field, rank_field
from curia_core.ingestion import deprivation
from tests.conftest import lsoa_row

INCOME_RANK = rank_field("Income")
INCOME_DECILE = decile_field("Income")
INCOME_RANK_DELTA = INCOME_RANK + " delta"
INCOME_DECILE_DELTA = INCOME_DECILE + " delta"


# --- rank_scales -------------------------------------------------------------


def test_rank_scales_returns_the_edition_max_per_rank_field():
    records = [
        lsoa_row("A", rank=100, decile=1),
        lsoa_row("B", rank=32844, decile=2),
        lsoa_row("C", rank=5, decile=3),
    ]
    scales = deprivation.rank_scales(records)

    assert scales[INCOME_RANK] == 32844.0
    assert set(scales) == {rank_field(d) for d in DOMAINS}  # decile fields excluded


def test_rank_scales_ignores_non_numeric_values():
    records = [lsoa_row("A", rank="n/a", decile=1), lsoa_row("B", rank=10, decile=1)]
    assert deprivation.rank_scales(records)[INCOME_RANK] == 10.0


def test_rank_scales_of_no_records_is_empty():
    assert deprivation.rank_scales([]) == {}


# --- aggregate_to_lad --------------------------------------------------------


def test_aggregate_to_lad_means_each_field_across_lsoas():
    records = [
        lsoa_row("Foo", rank=100, decile=6),
        lsoa_row("Foo", rank=300, decile=8),
        lsoa_row("Bar", rank=400, decile=2),
        lsoa_row("ZZ", rank=400, decile=10),  # pins the scale at 400
    ]
    aggregated = deprivation.aggregate_to_lad(records)

    assert aggregated["Foo"][INCOME_DECILE] == 7.0            # (6 + 8) / 2
    # Ranks are converted to percentile points of the edition max before meaning.
    assert aggregated["Foo"][INCOME_RANK] == pytest.approx(50.0)  # (25 + 75) / 2
    assert aggregated["Bar"][INCOME_RANK] == pytest.approx(100.0)


def test_aggregate_to_lad_skips_rows_with_no_lad_name():
    records = [
        lsoa_row("Foo", rank=10, decile=5),
        lsoa_row("", rank=10, decile=5),
        lsoa_row(None, rank=10, decile=5),
    ]
    assert set(deprivation.aggregate_to_lad(records)) == {"Foo"}


def test_aggregate_to_lad_omits_fields_with_no_numeric_values():
    records = [lsoa_row("Foo", rank=10, decile=5)]
    records[0][INCOME_DECILE] = "unknown"

    aggregated = deprivation.aggregate_to_lad(records)

    assert INCOME_DECILE not in aggregated["Foo"]
    assert INCOME_RANK in aggregated["Foo"]


def test_aggregate_to_lad_of_no_records_is_empty():
    assert deprivation.aggregate_to_lad([]) == {}


def test_aggregate_to_lad_raises_when_the_lad_column_is_missing():
    with pytest.raises(ValueError, match="no Local Authority District name column"):
        deprivation.aggregate_to_lad([{"Council": "Anytown"}])


def test_aggregate_to_lad_accepts_any_year_suffixed_lad_column():
    records = [
        lsoa_row("Foo", rank=10, decile=5, lad_column="Local Authority District name (2024)")
    ]
    assert "Foo" in deprivation.aggregate_to_lad(records)


# --- compute_deltas ----------------------------------------------------------


def test_compute_deltas_is_start_minus_end():
    start = deprivation.aggregate_to_lad(
        [lsoa_row("Foo", rank=10, decile=7), lsoa_row("ZZ", rank=100, decile=10)]
    )
    end = deprivation.aggregate_to_lad(
        [lsoa_row("Foo", rank=10, decile=4), lsoa_row("ZZ", rank=100, decile=10)]
    )
    deltas = deprivation.compute_deltas(start, end)

    assert deltas["Foo"][INCOME_DECILE_DELTA] == 3  # 7 - 4


def test_rank_delta_is_scale_free_across_editions_with_different_lsoa_counts():
    """IoD re-bases ranks every release (32,844 LSOAs in 2015/2019 vs 33,755 in 2025).
    A LAD sitting at the same percentile in both must show ~no change; differencing raw
    ranks would instead show a systematic offset proportional to the LAD's rank."""

    def edition(n_lsoas, fraction):
        return [
            lsoa_row("Foo", rank=int(n_lsoas * fraction), decile=5),
            lsoa_row("Filler", rank=n_lsoas, decile=5),
        ]

    deltas = deprivation.compute_deltas(
        deprivation.aggregate_to_lad(edition(32844, 0.25)),
        deprivation.aggregate_to_lad(edition(33755, 0.25)),
    )
    assert deltas["Foo"][INCOME_RANK_DELTA] == pytest.approx(0.0, abs=0.01)


def test_rank_deltas_are_rounded_floats_and_decile_deltas_are_ints():
    start = deprivation.aggregate_to_lad(
        [lsoa_row("Foo", rank=1234, decile=7), lsoa_row("ZZ", rank=32844, decile=10)]
    )
    end = deprivation.aggregate_to_lad(
        [lsoa_row("Foo", rank=999, decile=4), lsoa_row("ZZ", rank=32844, decile=10)]
    )
    entry = deprivation.compute_deltas(start, end)["Foo"]

    assert isinstance(entry[INCOME_RANK_DELTA], float)
    assert entry[INCOME_RANK_DELTA] == round(entry[INCOME_RANK_DELTA], 4)
    assert isinstance(entry[INCOME_DECILE_DELTA], int)


def test_compute_deltas_skips_lads_absent_from_the_end_year():
    start = deprivation.aggregate_to_lad(
        [lsoa_row("Gone", rank=10, decile=5), lsoa_row("Kept", rank=20, decile=5)]
    )
    end = deprivation.aggregate_to_lad([lsoa_row("Kept", rank=20, decile=5)])

    assert set(deprivation.compute_deltas(start, end)) == {"Kept"}


def test_compute_deltas_drops_lads_missing_any_of_the_sixteen_fields():
    """Partial rows would produce entries that fail the ingestion schema downstream."""
    start = deprivation.aggregate_to_lad([lsoa_row("Foo", rank=10, decile=5)])
    end = deprivation.aggregate_to_lad([lsoa_row("Foo", rank=10, decile=5)])
    del end["Foo"][INCOME_DECILE]

    assert deprivation.compute_deltas(start, end) == {}


def test_compute_deltas_emits_all_sixteen_keys_for_a_complete_lad():
    start = deprivation.aggregate_to_lad([lsoa_row("Foo", rank=10, decile=5)])
    end = deprivation.aggregate_to_lad([lsoa_row("Foo", rank=10, decile=3)])

    assert len(deprivation.compute_deltas(start, end)["Foo"]) == 16


def test_csv_deprivation_input_yields_no_numeric_fields():
    """Documents a real sharp edge rather than asserting desired behaviour.

    ``readers.read_records`` supports CSV, but ``csv.DictReader`` yields strings and
    ``aggregate_to_lad`` only accumulates ``int``/``float``. A CSV deprivation file
    therefore aggregates to empty dicts and produces ZERO deltas — silently, with only
    "could not compute deprivation delta" lines in the unused log to show for it.
    Production deprivation inputs are JSON (``data/deprivation_data/*.json``), so this
    does not bite today; this test exists so the behaviour is visible if that changes.
    """
    string_rows = [
        {k: str(v) for k, v in lsoa_row("Foo", rank=10, decile=5).items()},
    ]
    string_rows[0]["Local Authority District name (2019)"] = "Foo"

    aggregated = deprivation.aggregate_to_lad(string_rows)

    assert aggregated == {"Foo": {}}
    assert deprivation.compute_deltas(aggregated, aggregated) == {}
