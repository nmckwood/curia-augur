"""Tests for curia_core.ml.predict — the cross-analysis prediction stage: common-index
selection, the train/test split, model fitting, the no-ML majority baseline, and the
write-back of per-constituency predictions."""

import json

import numpy as np
import pytest

from curia_core.common.io import validation_errors
from curia_core.common.schemas import ML_FEATURE_KEYS, ml_output_schema
from curia_core.ml import predict
from tests.conftest import ingestion_entry


# --- common_indices ----------------------------------------------------------


def test_common_indices_is_the_intersection_in_first_list_order():
    assert predict.common_indices([["A", "B", "C"], ["C", "B", "D"]]) == ["B", "C"]


def test_common_indices_falls_back_to_each_lists_best_when_disjoint():
    """There must always be something to predict with."""
    assert predict.common_indices([["A", "B"], ["C", "D"]]) == ["A", "C"]


def test_common_indices_fallback_does_not_duplicate_a_shared_best():
    assert predict.common_indices([["A", "B"], ["A", "C"]]) == ["A"]


def test_common_indices_of_nothing_is_empty():
    assert predict.common_indices([]) == []


def test_common_indices_of_a_single_list_is_that_list():
    assert predict.common_indices([["A", "B"]]) == ["A", "B"]


# --- _split ------------------------------------------------------------------


def test_split_holds_out_a_genuine_test_set():
    targets = np.array([0] * 30 + [1] * 30)

    train_idx, test_idx = predict._split(targets)

    assert len(train_idx) + len(test_idx) == 60
    assert set(train_idx.tolist()) & set(test_idx.tolist()) == set()
    assert len(test_idx) == pytest.approx(60 * predict.TEST_SIZE, abs=1)


def test_split_is_stratified_so_both_classes_appear_in_the_test_set():
    targets = np.array([0] * 50 + [1] * 10)
    _train_idx, test_idx = predict._split(targets)
    assert set(targets[test_idx].tolist()) == {0, 1}


@pytest.mark.parametrize(
    "targets",
    [
        np.array([0, 1, 0]),        # fewer than 4 rows
        np.array([1] * 10),         # single class
        np.array([0] * 10 + [1]),   # a class with fewer than 2 members
    ],
)
def test_split_degrades_to_in_sample_for_inputs_that_cannot_be_held_out(targets):
    train_idx, test_idx = predict._split(targets)
    assert np.array_equal(train_idx, test_idx)
    assert len(train_idx) == len(targets)


def test_split_is_reproducible():
    targets = np.array([0] * 30 + [1] * 30)
    assert np.array_equal(predict._split(targets)[1], predict._split(targets)[1])


# --- _fit_eval ---------------------------------------------------------------


def test_fit_eval_scores_perfectly_on_a_separable_feature():
    n = 40
    matrix = np.array([[100.0] if i >= n // 2 else [-100.0] for i in range(n)])
    targets = np.array([1 if i >= n // 2 else 0 for i in range(n)])
    train_idx, test_idx = predict._split(targets)

    preds, metrics = predict._fit_eval(matrix, targets, train_idx, test_idx)

    assert len(test_idx) > 0 and len(train_idx) < n  # a real held-out split
    assert metrics["holdout_accuracy"] == 1.0
    assert metrics["train_accuracy"] == 1.0
    assert preds == targets.tolist()


def test_fit_eval_predicts_the_only_class_when_the_train_split_is_single_class():
    matrix = np.zeros((5, 2))
    targets = np.array([1, 1, 1, 1, 1])
    idx = np.arange(5)

    preds, metrics = predict._fit_eval(matrix, targets, idx, idx)

    assert preds == [1] * 5
    assert metrics["holdout_accuracy"] == 1.0


def test_fit_eval_returns_zero_accuracy_for_an_empty_index_set():
    matrix = np.zeros((4, 1))
    targets = np.array([0, 1, 0, 1])
    _preds, metrics = predict._fit_eval(
        matrix, targets, np.arange(4), np.array([], dtype=int)
    )
    assert metrics["holdout_accuracy"] == 0.0


def test_fit_eval_returns_plain_python_ints_for_json_serialisation():
    matrix = np.zeros((4, 1))
    targets = np.array([0, 1, 0, 1])
    preds, _ = predict._fit_eval(matrix, targets, np.arange(4), np.arange(4))
    assert all(isinstance(p, int) for p in preds)
    json.dumps(preds)  # must not raise


# --- _majority_baseline (the "no ML" bar) ------------------------------------


def test_majority_baseline_picks_the_train_majority_class():
    targets = np.array([0] * 8 + [1] * 2)
    idx = np.arange(10)

    baseline = predict._majority_baseline(targets, idx, idx)

    assert baseline["majority_class"] == 0
    assert baseline["all_accuracy"] == pytest.approx(0.8)
    assert baseline["n_correct_all"] == 8
    assert baseline["n_total_all"] == 10


def test_majority_baseline_can_be_the_change_class():
    targets = np.array([1] * 7 + [0] * 3)
    idx = np.arange(10)
    assert predict._majority_baseline(targets, idx, idx)["majority_class"] == 1


def test_majority_baseline_scores_holdout_and_all_separately():
    """The two numbers can differ: holdout is the test split, all_accuracy is everyone."""
    targets = np.array([0] * 6 + [1] * 4)
    train_idx = np.arange(6)          # all class 0
    test_idx = np.arange(6, 10)       # all class 1

    baseline = predict._majority_baseline(targets, train_idx, test_idx)

    assert baseline["majority_class"] == 0
    assert baseline["holdout_accuracy"] == 0.0
    assert baseline["all_accuracy"] == pytest.approx(0.6)


def test_majority_baseline_of_an_empty_train_split_is_a_safe_zero():
    targets = np.array([0, 1])
    baseline = predict._majority_baseline(targets, np.array([], dtype=int), np.arange(2))

    assert baseline["majority_class"] == 0
    assert baseline["holdout_accuracy"] == 0.0
    assert baseline["n_total_all"] == 2


def test_majority_baseline_of_an_empty_test_split_reports_zero_holdout():
    targets = np.array([0, 0, 1])
    baseline = predict._majority_baseline(
        targets, np.arange(3), np.array([], dtype=int)
    )
    assert baseline["holdout_accuracy"] == 0.0


# --- _rank_indices_by_coef / _univariate_accuracies --------------------------


def test_rank_indices_returns_k_names_from_the_feature_list():
    rng = np.random.RandomState(0)
    matrix = rng.normal(size=(40, len(ML_FEATURE_KEYS)))
    targets = np.array([0] * 20 + [1] * 20)
    matrix[20:, 3] += 10  # feature 3 separates the classes

    top = predict._rank_indices_by_coef(matrix, targets, np.arange(40), 5)

    assert len(top) == 5
    assert set(top) <= set(ML_FEATURE_KEYS)
    assert ML_FEATURE_KEYS[3] in top


def test_rank_indices_falls_back_to_the_first_k_for_a_single_class_train_split():
    matrix = np.zeros((5, len(ML_FEATURE_KEYS)))
    targets = np.ones(5, dtype=int)

    assert predict._rank_indices_by_coef(matrix, targets, np.arange(5), 3) == list(
        ML_FEATURE_KEYS[:3]
    )


def test_univariate_accuracies_covers_every_index_and_is_ranked():
    rng = np.random.RandomState(1)
    matrix = rng.normal(size=(40, len(ML_FEATURE_KEYS)))
    targets = np.array([0] * 20 + [1] * 20)
    train_idx, test_idx = predict._split(targets)

    details = predict._univariate_accuracies(matrix, targets, train_idx, test_idx)

    assert len(details) == len(ML_FEATURE_KEYS)
    assert [d["rank"] for d in details] == list(range(1, len(ML_FEATURE_KEYS) + 1))
    accuracies = [d["holdout_accuracy"] for d in details]
    assert accuracies == sorted(accuracies, reverse=True)


# --- key mapping -------------------------------------------------------------


def test_ingestion_key_is_derived_from_the_analysis_key():
    assert predict._ingestion_key_for("analysis/analysis-d_2015_d_2019.json") == (
        "output/deprivation-election-data-d_2015_d_2019.json"
    )


# --- run ---------------------------------------------------------------------


def _write_pair(output_dir, suffix, n=60, seed=0):
    """Write one ingestion output + a matching (unpredicted) analysis to local output."""
    rng = np.random.RandomState(seed)
    entries = []
    constituencies = []
    for i in range(n):
        change = 1 if i < n // 2 else 0
        # Feature 0 separates the classes, so the model has real signal to find.
        entry = ingestion_entry(f"LAD{i}_{suffix}", change_factor=change)
        entry["deprivation"][ML_FEATURE_KEYS[0]] = float(
            (10.0 if change else -10.0) + rng.normal(0, 0.5)
        )
        entries.append(entry)
        constituencies.append(
            {
                "Local Authority District name": entry["Local Authority District name"],
                "council": entry["local_election_results"]["council"],
                "cluster_id": change,
                "change_factor": change,
                "change_factor_cluster": change,
                "deprivation": dict(entry["deprivation"]),
                "pca_x": 0.0,
                "pca_y": 0.0,
            }
        )

    analysis = {
        "meta": {
            "k": 2,
            "k_selection_method": "silhouette",
            "features_used": list(ML_FEATURE_KEYS),
            "normalization": "z-score",
            "n_constituencies": n,
        },
        "clusters": [],
        "feature_importance": [],
        "constituencies": constituencies,
    }

    ingestion_key = f"output/deprivation-election-data-{suffix}.json"
    analysis_key = f"analysis/analysis-{suffix}.json"
    for key, payload in ((ingestion_key, entries), (analysis_key, analysis)):
        path = output_dir / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload), encoding="utf-8")
    return analysis_key


@pytest.fixture
def two_analyses(local_env):
    _data_dir, output_dir = local_env
    return [
        _write_pair(output_dir, "d_2015_d_2019_le_2018_le_2022", seed=0),
        _write_pair(output_dir, "d_2019_d_2025_le_2022_le_2026", seed=1),
    ], output_dir


def test_run_returns_common_indices_and_a_result_per_analysis(two_analyses):
    keys, _output_dir = two_analyses

    result = predict.run([{"analysis_key": k} for k in keys])

    assert result["key_indices"]
    assert len(result["results"]) == 2
    assert {r["analysis_key"] for r in result["results"]} == set(keys)


def test_run_writes_per_constituency_predictions_back(two_analyses):
    keys, output_dir = two_analyses

    predict.run([{"analysis_key": k} for k in keys])

    analysis = json.loads((output_dir / keys[0]).read_text())
    for c in analysis["constituencies"]:
        assert c["change_factor_deprivation_key_indices"] in (0, 1)
        assert c["change_factor_per_year_key_indices"] in (0, 1)


def test_run_populates_the_prediction_meta_block_including_the_baseline(two_analyses):
    keys, output_dir = two_analyses

    predict.run([{"analysis_key": k} for k in keys])

    meta = json.loads((output_dir / keys[0]).read_text())["meta"]
    prediction = meta["prediction"]

    assert meta["key_indices"]
    assert prediction["method"] == "logistic-regression"
    assert prediction["train_size"] + prediction["test_size"] == 60
    assert 0.0 <= prediction["holdout_accuracy"] <= 1.0
    # The flat field and the nested block must agree.
    assert prediction["baseline_accuracy"] == prediction["baseline"]["holdout_accuracy"]
    assert prediction["baseline"]["n_total_all"] == 60
    assert prediction["baseline"]["majority_class"] in (0, 1)
    assert len(prediction["per_year_index_details"]) == len(ML_FEATURE_KEYS)


def test_run_output_still_validates_against_the_ml_schema(two_analyses):
    keys, output_dir = two_analyses

    predict.run([{"analysis_key": k} for k in keys])

    for key in keys:
        analysis = json.loads((output_dir / key).read_text())
        assert validation_errors(analysis, ml_output_schema()) == []


def test_run_finds_real_signal_when_a_feature_separates_the_classes(two_analyses):
    keys, output_dir = two_analyses

    predict.run([{"analysis_key": k} for k in keys])

    prediction = json.loads((output_dir / keys[0]).read_text())["meta"]["prediction"]
    assert prediction["holdout_accuracy"] > prediction["baseline_accuracy"]


def test_run_accepts_an_explicit_ingestion_key(two_analyses):
    keys, _output_dir = two_analyses
    suffix = "d_2015_d_2019_le_2018_le_2022"

    result = predict.run(
        [
            {
                "analysis_key": keys[0],
                "ingestion_key": f"output/deprivation-election-data-{suffix}.json",
            },
            {"analysis_key": keys[1]},
        ]
    )

    assert len(result["results"]) == 2
