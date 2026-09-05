"""Tests for curia_core.common.io — the local-vs-S3 switch and schema validation.

The AWS branches are covered by swapping ``io._s3`` for the in-memory ``StubS3`` from
conftest, so no boto3, credentials or network access are involved.
"""

import json
import os

import pytest

from curia_core.common import io


# --- is_local ----------------------------------------------------------------


@pytest.mark.parametrize("value", ["1", "true", "TRUE", " yes ", "True"])
def test_is_local_accepts_the_documented_truthy_values(monkeypatch, value):
    monkeypatch.setenv("CURIA_LOCAL", value)
    assert io.is_local() is True


@pytest.mark.parametrize("value", ["0", "false", "no", "", "maybe"])
def test_is_local_rejects_everything_else(monkeypatch, value):
    monkeypatch.setenv("CURIA_LOCAL", value)
    assert io.is_local() is False


def test_is_local_defaults_to_false_when_unset(monkeypatch):
    monkeypatch.delenv("CURIA_LOCAL", raising=False)
    assert io.is_local() is False


# --- resolve_input_path ------------------------------------------------------


def test_resolve_input_path_finds_a_file_nested_under_the_data_dir(local_env):
    data_dir, _ = local_env
    nested = data_dir / "deprivation" / "2019"
    nested.mkdir(parents=True)
    (nested / "imd.csv").write_text("a,b\n1,2\n", encoding="utf-8")

    assert io.resolve_input_path("imd.csv") == str(nested / "imd.csv")


def test_resolve_input_path_raises_a_clear_error_when_missing(local_env):
    with pytest.raises(FileNotFoundError, match="nope.csv not found under"):
        io.resolve_input_path("nope.csv")


def test_resolve_input_path_downloads_from_s3_in_aws_mode(aws_env, stub_s3):
    stub_s3.objects[("test-input-bucket", "inputs/imd.csv")] = b"a,b\n1,2\n"

    path = io.resolve_input_path("inputs/imd.csv")

    assert path == os.path.join("/tmp", "imd.csv")
    assert stub_s3.downloads == [("test-input-bucket", "inputs/imd.csv", path)]
    with open(path, "rb") as fh:
        assert fh.read() == b"a,b\n1,2\n"


# --- write / read round trips ------------------------------------------------


def test_write_output_text_creates_nested_prefixes_locally(local_env):
    _, output_dir = local_env

    dest = io.write_output_text("output/nested/file.txt", "hello")

    assert dest == str(output_dir / "output" / "nested" / "file.txt")
    assert (output_dir / "output" / "nested" / "file.txt").read_text() == "hello"


def test_write_then_read_output_text_round_trips_locally(local_env):
    io.write_output_text("output/thing.txt", "round trip")
    assert io.read_output_text("output/thing.txt") == "round trip"


def test_write_output_json_pretty_prints_and_round_trips(local_env):
    io.write_output_json("output/thing.json", {"b": 1, "a": [1, 2]})

    raw = io.read_output_text("output/thing.json")
    assert "\n  " in raw  # indent=2
    assert json.loads(raw) == {"b": 1, "a": [1, 2]}


def test_write_output_text_puts_to_s3_and_returns_the_uri(aws_env, stub_s3):
    location = io.write_output_text("output/thing.txt", "hello")

    assert location == "s3://test-output-bucket/output/thing.txt"
    assert stub_s3.puts == [("test-output-bucket", "output/thing.txt", b"hello")]


def test_read_output_text_gets_from_s3(aws_env, stub_s3):
    stub_s3.objects[("test-output-bucket", "analysis/a.json")] = b'{"ok": true}'
    assert io.read_output_text("analysis/a.json") == '{"ok": true}'


# --- list_output_keys --------------------------------------------------------


def test_list_output_keys_walks_the_local_output_dir_and_sorts(local_env):
    io.write_output_text("analysis/b.json", "{}")
    io.write_output_text("analysis/a.json", "{}")
    io.write_output_text("output/other.json", "{}")

    assert io.list_output_keys("analysis/") == ["analysis/a.json", "analysis/b.json"]


def test_list_output_keys_returns_empty_for_an_absent_prefix(local_env):
    assert io.list_output_keys("analysis/") == []


def test_list_output_keys_paginates_in_aws_mode(aws_env, stub_s3):
    for name in ("c", "a", "b"):
        stub_s3.objects[("test-output-bucket", f"analysis/{name}.json")] = b"{}"
    stub_s3.objects[("test-output-bucket", "output/skip.json")] = b"{}"

    # StubS3 splits results across two pages, so this also proves the loop over pages.
    assert io.list_output_keys("analysis/") == [
        "analysis/a.json",
        "analysis/b.json",
        "analysis/c.json",
    ]


# --- validation_errors -------------------------------------------------------

_SCHEMA = {
    "type": "object",
    "properties": {"name": {"type": "string"}, "n": {"type": "integer"}},
    "required": ["name"],
    "additionalProperties": False,
}


def test_validation_errors_returns_empty_for_a_valid_instance():
    assert io.validation_errors({"name": "ok", "n": 1}, _SCHEMA) == []


def test_validation_errors_reports_the_path_and_never_raises():
    errors = io.validation_errors({"name": 1, "n": "x"}, _SCHEMA)

    assert len(errors) == 2
    assert any(e.startswith("name:") for e in errors)
    assert any(e.startswith("n:") for e in errors)


def test_validation_errors_labels_root_level_problems():
    errors = io.validation_errors({}, _SCHEMA)
    assert errors == ["<root>: 'name' is a required property"]
