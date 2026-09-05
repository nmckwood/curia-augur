"""Tests for curia_core.ingestion.pipeline — the orchestration that reads four input
files, joins them and writes the output JSON plus the unused-data log.

These run entirely against local tmp dirs (``CURIA_LOCAL=true``), which is exactly the
path ``tools/run_ingestion_local.py`` uses.
"""

import csv
import json

import pytest

from curia_core.common.schemas import DECILE_DELTA_KEYS, ingestion_output_schema
from curia_core.common.io import validation_errors
from curia_core.ingestion import pipeline
from tests.conftest import councillor_rows, lsoa_row


# --- helpers -----------------------------------------------------------------


def _write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


@pytest.fixture
def ingestion_inputs(local_env):
    """Write a minimal but complete four-file input set into the local data dir.

    Three LADs/councils that join cleanly, plus one council that is abolished by the
    target year and one deprivation LAD with no election counterpart, so the log has
    something real in it.
    """
    data_dir, output_dir = local_env

    def edition(offset, decile_offset):
        rows = []
        for name in ("Alpha", "Bravo", "Charlie", "Orphanshire"):
            rows.append(
                lsoa_row(name, rank=1000 + offset, decile=5 + decile_offset)
            )
        rows.append(lsoa_row("ZZ Filler", rank=32844, decile=10))
        return rows

    # Deprivation inputs are JSON in production (numeric values); election inputs are
    # CSV. Matching that here matters: CSV yields strings, and the numeric fields would
    # be silently skipped (see test_csv_deprivation_input_yields_no_numeric_fields).
    (data_dir / "dep_2015.json").write_text(json.dumps(edition(0, 0)), encoding="utf-8")
    (data_dir / "dep_2019.json").write_text(
        json.dumps(edition(500, -2)), encoding="utf-8"
    )

    _write_csv(
        data_dir / "elect_2018.csv",
        councillor_rows(
            {
                "Alpha": {"Labour": 3, "Conservative": 1},
                "Bravo": {"Conservative": 4},
                "Charlie": {"Labour": 2},
                "Abolishedshire": {"Labour": 2},
            }
        ),
    )
    _write_csv(
        data_dir / "elect_2022.csv",
        councillor_rows(
            {
                "Alpha": {"Conservative": 3, "Labour": 1},  # flip -> 1
                "Bravo": {"Conservative": 2},               # hold -> 0
                "Charlie": {"Labour": 3},                   # hold -> 0
            }
        ),
    )

    return {
        "deprivation_file_start": "dep_2015.json",
        "deprivation_file_end": "dep_2019.json",
        "local_election_start": "elect_2018.csv",
        "local_election_end": "elect_2022.csv",
    }, output_dir


# --- key derivation ----------------------------------------------------------


@pytest.mark.parametrize(
    ("filename", "expected"),
    [
        ("File_7_-_All_IoD2019_Scores__2019.xlsx", "2019"),
        ("imd2015.csv", "2015"),
        ("councillors-2026.csv", "2026"),
        ("no-year-here.csv", "unknown"),
        ("1899_too_early.csv", "unknown"),
    ],
)
def test_year_extraction(filename, expected):
    assert pipeline._year(filename) == expected


def test_composite_key_joins_all_four_years():
    key = pipeline._composite_key(
        {
            "deprivation_file_start": "imd2015.xlsx",
            "deprivation_file_end": "imd2019.xlsx",
            "local_election_start": "e2018.csv",
            "local_election_end": "e2022.csv",
        }
    )
    assert key == "d_2015_d_2019_le_2018_le_2022"


def test_lambda_event_from_s3_is_a_passthrough():
    event = {"deprivation_file_start": "a.csv"}
    assert pipeline.lambda_event_from_s3(event) is event


def test_feature_keys_reexport_matches_the_decile_deltas():
    assert pipeline.FEATURE_KEYS == DECILE_DELTA_KEYS


# --- run ---------------------------------------------------------------------


def test_run_writes_a_schema_valid_output_and_a_log(ingestion_inputs):
    event, output_dir = ingestion_inputs

    result = pipeline.run(event)

    assert result["composite_key"] == "d_2015_d_2019_le_2018_le_2022"
    assert result["output_key"] == (
        "output/deprivation-election-data-d_2015_d_2019_le_2018_le_2022.json"
    )
    written = output_dir / result["output_key"]
    assert written.exists()

    entries = json.loads(written.read_text())
    assert result["n_entries"] == len(entries) == 3
    assert validation_errors(entries, ingestion_output_schema()) == []


def test_run_carries_the_majority_flip_through_to_the_output(ingestion_inputs):
    event, output_dir = ingestion_inputs

    result = pipeline.run(event)
    entries = json.loads((output_dir / result["output_key"]).read_text())
    by_council = {e["local_election_results"]["council"]: e for e in entries}

    assert by_council["Alpha"]["local_election_results"]["change_factor"] == 1
    assert by_council["Bravo"]["local_election_results"]["change_factor"] == 0
    assert by_council["Charlie"]["local_election_results"]["change_factor"] == 0


def test_run_logs_abolished_councils_and_unused_deprivation_lads(ingestion_inputs):
    event, output_dir = ingestion_inputs

    pipeline.run(event)

    log = (
        output_dir
        / "output"
        / "unused-deprivation-election-data-d_2015_d_2019_le_2018_le_2022.log"
    ).read_text()

    assert "dropped council 'Abolishedshire'" in log
    assert "no successor council" in log
    assert "deprivation LAD 'Orphanshire' had no matching election council" in log


def test_run_reports_the_log_line_count(ingestion_inputs):
    event, _ = ingestion_inputs
    result = pipeline.run(event)
    # Abolishedshire dropped + Orphanshire unused + the ZZ Filler LAD unused.
    assert result["n_unused"] >= 2


def test_run_logs_lads_whose_delta_cannot_be_computed(ingestion_inputs, local_env):
    """A LAD present in only one deprivation edition has no delta and must be logged."""
    event, output_dir = ingestion_inputs
    data_dir, _ = local_env

    rows = json.loads((data_dir / "dep_2015.json").read_text())
    rows.append(lsoa_row("OnlyInStartYear", rank=1000, decile=5))
    (data_dir / "dep_2015.json").write_text(json.dumps(rows), encoding="utf-8")

    pipeline.run(event)

    log = (
        output_dir
        / "output"
        / "unused-deprivation-election-data-d_2015_d_2019_le_2018_le_2022.log"
    ).read_text()
    assert "could not compute deprivation delta for 'OnlyInStartYear'" in log


def test_run_logs_councils_that_cannot_be_joined(ingestion_inputs, local_env):
    event, output_dir = ingestion_inputs
    data_dir, _ = local_env

    for name in ("elect_2018.csv", "elect_2022.csv"):
        rows = list(csv.DictReader(open(data_dir / name, encoding="utf-8")))
        rows.extend(councillor_rows({"Qzxwv Fictional": {"Labour": 2}}))
        _write_csv(data_dir / name, rows)

    pipeline.run(event)

    log = (
        output_dir
        / "output"
        / "unused-deprivation-election-data-d_2015_d_2019_le_2018_le_2022.log"
    ).read_text()
    assert "could not join council 'Qzxwv Fictional'" in log


def test_run_drops_and_logs_entries_that_fail_schema_validation(
    ingestion_inputs, monkeypatch
):
    """A malformed delta must be logged and excluded, not written out."""
    event, output_dir = ingestion_inputs
    real_compute = pipeline.deprivation.compute_deltas

    def corrupt(start, end):
        deltas = real_compute(start, end)
        if "Alpha" in deltas:
            deltas["Alpha"]["unexpected extra field"] = 1
        return deltas

    monkeypatch.setattr(pipeline.deprivation, "compute_deltas", corrupt)

    result = pipeline.run(event)

    entries = json.loads((output_dir / result["output_key"]).read_text())
    assert "Alpha" not in {e["Local Authority District name"] for e in entries}

    log = (
        output_dir
        / "output"
        / "unused-deprivation-election-data-d_2015_d_2019_le_2018_le_2022.log"
    ).read_text()
    assert "due to validation errors" in log


def test_run_is_deterministic(ingestion_inputs):
    event, output_dir = ingestion_inputs

    first = json.loads((output_dir / pipeline.run(event)["output_key"]).read_text())
    second = json.loads((output_dir / pipeline.run(event)["output_key"]).read_text())

    assert first == second
