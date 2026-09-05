"""Shared fixtures and synthetic-data builders for the Curia Augur test suite.

Every test runs fully offline: the AWS branches of ``curia_core.common.io`` are exercised
with a stub S3 client injected in place of ``io._s3`` (boto3 is imported lazily, so it is
never needed), and everything else runs against ``CURIA_LOCAL=true`` pointed at tmp dirs.
See tests/README.md for how to run the suite.
"""

import csv
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from curia_core.common.schemas import (  # noqa: E402
    DOMAINS,
    decile_field,
    rank_field,
)

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


# --- Environment -------------------------------------------------------------


@pytest.fixture
def local_env(tmp_path, monkeypatch):
    """Point the IO layer at throwaway local data/output dirs in local mode.

    Returns ``(data_dir, output_dir)``.
    """
    data_dir = tmp_path / "data"
    output_dir = tmp_path / "local_output"
    data_dir.mkdir()
    output_dir.mkdir()
    monkeypatch.setenv("CURIA_LOCAL", "true")
    monkeypatch.setenv("CURIA_LOCAL_DATA_DIR", str(data_dir))
    monkeypatch.setenv("CURIA_LOCAL_OUTPUT_DIR", str(output_dir))
    return data_dir, output_dir


@pytest.fixture
def aws_env(monkeypatch):
    """AWS mode with bucket names set. Pair with :class:`StubS3` via ``stub_s3``."""
    monkeypatch.delenv("CURIA_LOCAL", raising=False)
    monkeypatch.setenv("INPUT_BUCKET", "test-input-bucket")
    monkeypatch.setenv("OUTPUT_BUCKET", "test-output-bucket")


class StubS3:
    """Minimal in-memory stand-in for the boto3 S3 client.

    Only the four calls the IO layer makes are implemented. This is deliberately a hand
    written stub rather than moto: the surface is tiny, and it keeps the suite dependency
    free and fast.
    """

    def __init__(self, objects=None):
        self.objects = dict(objects or {})  # (bucket, key) -> bytes
        self.downloads = []
        self.puts = []

    def download_file(self, bucket, key, dest):
        self.downloads.append((bucket, key, dest))
        with open(dest, "wb") as fh:
            fh.write(self.objects.get((bucket, key), b""))

    def put_object(self, Bucket, Key, Body):  # noqa: N803 - boto3 kwarg casing
        self.puts.append((Bucket, Key, Body))
        self.objects[(Bucket, Key)] = Body

    def get_object(self, Bucket, Key):  # noqa: N803 - boto3 kwarg casing
        if (Bucket, Key) not in self.objects:
            raise KeyError(f"no such object s3://{Bucket}/{Key}")
        body = self.objects[(Bucket, Key)]

        class _Body:
            def read(self_inner):
                return body

        return {"Body": _Body()}

    def get_paginator(self, _operation):
        stub = self

        class _Paginator:
            def paginate(self_inner, Bucket, Prefix):  # noqa: N803
                contents = [
                    {"Key": key}
                    for (bucket, key) in sorted(stub.objects)
                    if bucket == Bucket and key.startswith(Prefix)
                ]
                # Two pages, to prove the pagination loop is exercised.
                yield {"Contents": contents[:1]}
                yield {"Contents": contents[1:]}

        return _Paginator()


@pytest.fixture
def stub_s3(monkeypatch):
    """Replace ``io._s3`` with an in-memory stub and hand it back to the test."""
    from curia_core.common import io

    stub = StubS3()
    monkeypatch.setattr(io, "_s3", lambda: stub)
    return stub


# --- Synthetic data builders -------------------------------------------------


def lsoa_row(lad, *, rank, decile, lad_column="Local Authority District name (2019)"):
    """One LSOA-level deprivation row with all 16 rank/decile fields set uniformly."""
    row = {lad_column: lad}
    for domain in DOMAINS:
        row[rank_field(domain)] = rank
        row[decile_field(domain)] = decile
    return row


def deprivation_edition(lads, *, rank, decile, max_rank=32844):
    """An LSOA table for one IoD edition.

    ``lads`` maps LAD name -> (rank, decile) overrides; ``rank``/``decile`` are defaults.
    A filler row pins the edition's maximum rank, which is what ``rank_scales`` uses to
    convert ranks to national percentiles.
    """
    rows = []
    for lad, override in lads.items():
        lad_rank, lad_decile = override if override else (rank, decile)
        rows.append(lsoa_row(lad, rank=lad_rank, decile=lad_decile))
    rows.append(lsoa_row("ZZ Filler", rank=max_rank, decile=10))
    return rows


def councillor_rows(seats):
    """Election rows from ``{council: {party: n_councillors}}`` (one row per councillor)."""
    rows = []
    for council, parties in seats.items():
        for party, count in parties.items():
            rows.extend(
                {"Council": council, "Party Name": party} for _ in range(count)
            )
    return rows


def ingestion_entry(lad, *, change_factor, delta=1.0, council=None):
    """One entry in the ingestion output format (the ML pipeline's input)."""
    deprivation = {}
    for i, domain in enumerate(DOMAINS):
        deprivation[rank_field(domain) + " delta"] = round(delta + i * 0.5, 4)
        deprivation[decile_field(domain) + " delta"] = int(delta) + i
    return {
        "Local Authority District name": lad,
        "deprivation": deprivation,
        "local_election_results": {
            "council": council or f"{lad} Council",
            "change_factor": change_factor,
        },
    }


@pytest.fixture
def write_csv(tmp_path):
    """Write rows to a CSV under tmp_path and return the path."""

    def _write(name, rows):
        path = tmp_path / name
        with open(path, "w", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        return str(path)

    return _write


@pytest.fixture
def write_json(tmp_path):
    """Write an object to a JSON file under tmp_path and return the path."""

    def _write(name, obj):
        path = tmp_path / name
        path.write_text(json.dumps(obj), encoding="utf-8")
        return str(path)

    return _write
