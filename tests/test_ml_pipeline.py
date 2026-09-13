"""Tests for curia_core.ml.pipeline — event parsing, key derivation, and the full
clustering run that writes analysis/analysis-<key>.json."""

import json

import pytest

from curia_core.common.io import validation_errors
from curia_core.common.schemas import ML_FEATURE_KEYS, ml_output_schema
from curia_core.ml import pipeline
from tests.conftest import ingestion_entry


# --- event / key handling ----------------------------------------------------


def test_output_key_taken_from_a_direct_invocation():
    event = {"output_key": "output/deprivation-election-data-d_2015.json"}
    assert pipeline._output_key_from_event(event) == event["output_key"]


def test_output_key_taken_from_an_s3_event_record():
    event = {"Records": [{"s3": {"object": {"key": "output/foo.json"}}}]}
    assert pipeline._output_key_from_event(event) == "output/foo.json"


def test_output_key_from_a_direct_key_wins_over_records():
    event = {
        "output_key": "output/direct.json",
        "Records": [{"s3": {"object": {"key": "output/from-event.json"}}}],
    }
    assert pipeline._output_key_from_event(event) == "output/direct.json"


@pytest.mark.parametrize("event", [{}, {"Records": []}, {"other": 1}])
def test_output_key_raises_on_an_unrecognised_event(event):
    with pytest.raises(ValueError, match="neither 'output_key' nor S3 Records"):
        pipeline._output_key_from_event(event)


@pytest.mark.parametrize(
    ("key", "expected"),
    [
        (
            "output/deprivation-election-data-d_2015_d_2019_le_2018_le_2022.json",
            "d_2015_d_2019_le_2018_le_2022",
        ),
        ("deprivation-election-data-x.json", "x"),
        ("output/something-else.json", "something-else.json"),
    ],
)
def test_composite_key_extraction(key, expected):
    assert pipeline._composite_key(key) == expected


# --- run ---------------------------------------------------------------------


@pytest.fixture
def ingestion_output(local_env):
    """Write a synthetic ingestion output with two separable deprivation profiles.

    Half the LADs have a low-delta profile and never flip; the other half have a
    high-delta profile and mostly flip, so KMeans has something real to find.
    """
    _data_dir, output_dir = local_env
    entries = []
    for i in range(30):
        entries.append(ingestion_entry(f"Low{i}", change_factor=0, delta=1.0 + i * 0.01))
    for i in range(30):
        entries.append(
            ingestion_entry(f"High{i}", change_factor=1 if i < 25 else 0, delta=50.0 + i * 0.01)
        )
    key = "output/deprivation-election-data-d_2015_d_2019_le_2018_le_2022.json"
    path = output_dir / key
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(entries), encoding="utf-8")
    return key, output_dir, entries


def test_run_writes_a_schema_valid_analysis(ingestion_output):
    key, output_dir, entries = ingestion_output

    result = pipeline.run({"output_key": key})

    assert result["analysis_key"] == (
        "analysis/analysis-d_2015_d_2019_le_2018_le_2022.json"
    )
    assert result["n_constituencies"] == len(entries)

    analysis = json.loads((output_dir / result["analysis_key"]).read_text())
    assert validation_errors(analysis, ml_output_schema()) == []


def test_run_meta_records_how_the_model_was_configured(ingestion_output):
    key, output_dir, entries = ingestion_output

    pipeline.run({"output_key": key})
    meta = json.loads(
        (output_dir / "analysis/analysis-d_2015_d_2019_le_2018_le_2022.json").read_text()
    )["meta"]

    assert meta["k"] >= 2
    assert meta["k_selection_method"] == "silhouette"
    assert meta["normalization"] == "z-score"
    assert meta["features_used"] == list(ML_FEATURE_KEYS)
    assert meta["n_constituencies"] == len(entries)
    assert "generated_at" in meta


def test_run_flags_exactly_one_high_change_cluster(ingestion_output):
    key, output_dir, _ = ingestion_output

    pipeline.run({"output_key": key})
    analysis = json.loads(
        (output_dir / "analysis/analysis-d_2015_d_2019_le_2018_le_2022.json").read_text()
    )

    assert sum(c["is_high_change_cluster"] for c in analysis["clusters"]) == 1


def test_run_sets_change_factor_cluster_from_the_high_change_cluster(ingestion_output):
    """REQUIREMENTS_4 ML-1: 1 iff the constituency sits in the high-change cluster."""
    key, output_dir, _ = ingestion_output

    pipeline.run({"output_key": key})
    analysis = json.loads(
        (output_dir / "analysis/analysis-d_2015_d_2019_le_2018_le_2022.json").read_text()
    )
    high_ids = {
        c["cluster_id"] for c in analysis["clusters"] if c["is_high_change_cluster"]
    }

    for c in analysis["constituencies"]:
        expected = 1 if c["cluster_id"] in high_ids else 0
        assert c["change_factor_cluster"] == expected


def test_run_scores_and_ranks_every_cluster(ingestion_output):
    key, output_dir, _ = ingestion_output

    pipeline.run({"output_key": key})
    analysis = json.loads(
        (output_dir / "analysis/analysis-d_2015_d_2019_le_2018_le_2022.json").read_text()
    )

    ranks = sorted(c["accuracy_rank"] for c in analysis["clusters"])
    assert ranks == list(range(1, len(analysis["clusters"]) + 1))
    assert all(0.0 <= c["accuracy"] <= 1.0 for c in analysis["clusters"])


def test_run_cluster_accuracy_matches_the_per_constituency_data(ingestion_output):
    key, output_dir, _ = ingestion_output

    pipeline.run({"output_key": key})
    analysis = json.loads(
        (output_dir / "analysis/analysis-d_2015_d_2019_le_2018_le_2022.json").read_text()
    )

    overall = analysis["meta"]["cluster_accuracy"]
    expected = sum(
        1
        for c in analysis["constituencies"]
        if c["change_factor_cluster"] == c["change_factor"]
    )
    assert overall["n_correct"] == expected
    assert overall["n_total"] == len(analysis["constituencies"])


def test_run_gives_every_constituency_pca_coordinates(ingestion_output):
    key, output_dir, _ = ingestion_output

    pipeline.run({"output_key": key})
    analysis = json.loads(
        (output_dir / "analysis/analysis-d_2015_d_2019_le_2018_le_2022.json").read_text()
    )

    assert all("pca_x" in c and "pca_y" in c for c in analysis["constituencies"])


def test_run_ranks_feature_importance(ingestion_output):
    key, output_dir, _ = ingestion_output

    pipeline.run({"output_key": key})
    analysis = json.loads(
        (output_dir / "analysis/analysis-d_2015_d_2019_le_2018_le_2022.json").read_text()
    )

    ranks = [f["rank"] for f in analysis["feature_importance"]]
    assert ranks == list(range(1, len(ranks) + 1))


def test_run_accepts_an_s3_style_event(ingestion_output):
    key, _output_dir, _ = ingestion_output

    result = pipeline.run({"Records": [{"s3": {"object": {"key": key}}}]})

    assert result["analysis_key"].startswith("analysis/analysis-")


def test_run_raises_rather_than_writing_an_invalid_analysis(
    ingestion_output, monkeypatch
):
    """A schema break must fail loudly; a silently malformed analysis would break the
    prediction stage and the UI downstream."""
    key, _output_dir, _ = ingestion_output

    monkeypatch.setattr(
        pipeline.stats,
        "cluster_summaries",
        lambda labels, changes, matrix: [{"cluster_id": "not-an-int"}],
    )
    monkeypatch.setattr(pipeline.stats, "mark_high_change_cluster", lambda s: 0)
    monkeypatch.setattr(
        pipeline.stats,
        "score_clusters",
        lambda summaries, labels, changes, high: ([0] * len(changes), {}),
    )

    with pytest.raises(ValueError, match="failed schema validation"):
        pipeline.run({"output_key": key})
