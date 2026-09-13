"""Tests for curia_core.ingestion.readers — file-type dispatch and LAD column detection."""

import json

import pytest

from curia_core.ingestion import readers


def test_read_records_reads_csv_rows_as_dicts(write_csv):
    path = write_csv("in.csv", [{"a": "1", "b": "x"}, {"a": "2", "b": "y"}])
    assert readers.read_records(path) == [
        {"a": "1", "b": "x"},
        {"a": "2", "b": "y"},
    ]


def test_read_records_strips_a_utf8_bom_from_csv_headers(tmp_path):
    """Government CSV exports are routinely BOM-prefixed; the first column name would
    otherwise come back as '\\ufeffCouncil' and silently fail every lookup."""
    path = tmp_path / "bom.csv"
    path.write_bytes("﻿Council,Party Name\nAnytown,Labour\n".encode("utf-8"))

    assert readers.read_records(str(path)) == [
        {"Council": "Anytown", "Party Name": "Labour"}
    ]


def test_read_records_reads_a_json_list(write_json):
    path = write_json("in.json", [{"a": 1}, {"a": 2}])
    assert readers.read_records(path) == [{"a": 1}, {"a": 2}]


def test_read_records_unwraps_a_records_key(write_json):
    path = write_json("in.json", {"records": [{"a": 1}]})
    assert readers.read_records(path) == [{"a": 1}]


def test_read_records_wraps_a_bare_json_object_as_one_record(write_json):
    path = write_json("in.json", {"a": 1})
    assert readers.read_records(path) == [{"a": 1}]


def test_read_records_reads_xlsx_via_pandas(tmp_path):
    pd = pytest.importorskip("pandas")
    path = tmp_path / "in.xlsx"
    pd.DataFrame([{"a": 1, "b": "x"}]).to_excel(path, index=False)

    assert readers.read_records(str(path)) == [{"a": 1, "b": "x"}]


@pytest.mark.parametrize("name", ["data.txt", "data.parquet", "data"])
def test_read_records_rejects_unsupported_extensions(tmp_path, name):
    path = tmp_path / name
    path.write_text("whatever", encoding="utf-8")

    with pytest.raises(ValueError, match="unsupported file type"):
        readers.read_records(str(path))


@pytest.mark.parametrize(
    "column",
    [
        "Local Authority District name",
        "Local Authority District name (2013)",
        "Local Authority District name (2019)",
        "Local Authority District name (2024)",
    ],
)
def test_detect_lad_column_ignores_the_varying_year_suffix(column):
    """Each IoD edition suffixes the column with a different year."""
    assert readers.detect_lad_column({column: "Testshire", "other": 1}) == column


def test_detect_lad_column_returns_none_when_absent():
    assert readers.detect_lad_column({"Council": "Anytown"}) is None


def test_read_json_handles_unicode(tmp_path):
    path = tmp_path / "u.json"
    path.write_text(json.dumps([{"lad": "Ynys Môn"}]), encoding="utf-8")
    assert readers.read_records(str(path))[0]["lad"] == "Ynys Môn"
