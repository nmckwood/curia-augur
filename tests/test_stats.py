"""Tests for curia_core.ml.stats — per-cluster change_factor summaries, the high-change
flag, feature importance, and the REQUIREMENTS_4 scoring of
each cluster's implied prediction."""

import numpy as np
import pytest

from curia_core.common.schemas import ML_FEATURE_KEYS
from curia_core.ml import stats

N_FEATURES = len(ML_FEATURE_KEYS)


def _two_clusters(change_a, change_b):
    """Labels/changes/matrix for two clusters of len(change_a) and len(change_b)."""
    labels = np.array([0] * len(change_a) + [1] * len(change_b))
    matrix = np.vstack(
        [np.zeros((len(change_a), N_FEATURES)), np.ones((len(change_b), N_FEATURES))]
    )
    return labels, list(change_a) + list(change_b), matrix


# --- cluster_summaries -------------------------------------------------------


def test_cluster_summaries_reports_size_mean_median_and_centroid():
    labels, changes, matrix = _two_clusters([0, 0, 1, 1], [1, 1, 1, 0])

    summaries = stats.cluster_summaries(labels, changes, matrix)

    assert [s["cluster_id"] for s in summaries] == [0, 1]
    assert summaries[0]["size"] == 4
    assert summaries[0]["mean_change_factor"] == pytest.approx(0.5)
    assert summaries[0]["median_change_factor"] == pytest.approx(0.5)
    assert summaries[1]["mean_change_factor"] == pytest.approx(0.75)
    assert set(summaries[0]["centroid"]) == set(ML_FEATURE_KEYS)
    assert summaries[1]["centroid"][ML_FEATURE_KEYS[0]] == pytest.approx(1.0)


def test_cluster_summaries_are_sorted_by_cluster_id():
    labels = np.array([2, 0, 1, 0])
    matrix = np.zeros((4, N_FEATURES))
    summaries = stats.cluster_summaries(labels, [0, 1, 0, 1], matrix)
    assert [s["cluster_id"] for s in summaries] == [0, 1, 2]


def test_cluster_summaries_start_with_the_high_change_flag_unset():
    labels, changes, matrix = _two_clusters([0], [1])
    assert all(
        s["is_high_change_cluster"] is False
        for s in stats.cluster_summaries(labels, changes, matrix)
    )


# --- mark_high_change_cluster ------------------------------------------------


def test_mark_high_change_flags_exactly_the_highest_mean_cluster():
    labels, changes, matrix = _two_clusters([0, 0, 0, 1], [1, 1, 1, 0])
    summaries = stats.cluster_summaries(labels, changes, matrix)

    high = stats.mark_high_change_cluster(summaries)

    assert high == 1
    assert [s["is_high_change_cluster"] for s in summaries] == [False, True]


def test_mark_high_change_of_no_summaries_returns_none():
    assert stats.mark_high_change_cluster([]) is None

# --- feature_importance ------------------------------------------------------


def test_feature_importance_ranks_by_deviation_and_is_one_indexed():
    labels = np.array([0] * 10 + [1] * 10)
    matrix = np.zeros((20, N_FEATURES))
    matrix[10:, 0] = 5.0   # biggest separation
    matrix[10:, 1] = 1.0   # smaller separation

    ranked = stats.feature_importance(labels, matrix, high_change_cluster_id=1)

    assert len(ranked) == N_FEATURES
    assert [r["rank"] for r in ranked] == list(range(1, N_FEATURES + 1))
    assert ranked[0]["feature"] == ML_FEATURE_KEYS[0]
    assert ranked[0]["deviation_score"] == pytest.approx(5.0)
    assert ranked[1]["feature"] == ML_FEATURE_KEYS[1]
    assert ranked[-1]["deviation_score"] == pytest.approx(0.0)


def test_feature_importance_reports_both_group_means():
    labels = np.array([0] * 5 + [1] * 5)
    matrix = np.zeros((10, N_FEATURES))
    matrix[5:, 0] = 4.0

    top = stats.feature_importance(labels, matrix, 1)[0]

    assert top["high_change_cluster_mean"] == pytest.approx(4.0)
    assert top["other_clusters_mean"] == pytest.approx(0.0)


def test_feature_importance_survives_a_high_change_id_matching_every_row():
    """No 'other' rows: the other-cluster mean falls back to 0 rather than raising."""
    labels = np.zeros(5, dtype=int)
    matrix = np.ones((5, N_FEATURES))

    ranked = stats.feature_importance(labels, matrix, 0)

    assert ranked[0]["other_clusters_mean"] == 0.0


# --- cluster_predictions / score_clusters (REQUIREMENTS_4) -------------------


def test_cluster_predictions_are_one_only_inside_the_high_change_cluster():
    labels = np.array([0, 1, 1, 0, 2])
    assert stats.cluster_predictions(labels, 1) == [0, 1, 1, 0, 0]


def test_cluster_predictions_of_a_none_high_change_id_are_all_zero():
    assert stats.cluster_predictions(np.array([0, 1]), None) == [0, 0]


def test_score_clusters_computes_per_cluster_accuracy_and_ranks_them():
    # Cluster 0 correctly calls "no change" for 8 of 10; cluster 1 (high change)
    # correctly calls "change" for 6 of 10.
    labels = np.array([0] * 10 + [1] * 10)
    changes = [0] * 8 + [1] * 2 + [1] * 6 + [0] * 4
    matrix = np.vstack([np.zeros((10, N_FEATURES)), np.ones((10, N_FEATURES))])
    summaries = stats.cluster_summaries(labels, changes, matrix)
    high = stats.mark_high_change_cluster(summaries)

    predictions, overall = stats.score_clusters(summaries, labels, changes, high)

    assert high == 1
    assert predictions == [0] * 10 + [1] * 10
    assert summaries[0]["predicted_change_factor"] == 0
    assert summaries[1]["predicted_change_factor"] == 1
    assert summaries[0]["accuracy"] == pytest.approx(0.8)
    assert summaries[0]["n_correct"] == 8
    assert summaries[1]["accuracy"] == pytest.approx(0.6)
    assert summaries[0]["accuracy_rank"] == 1
    assert summaries[1]["accuracy_rank"] == 2
    assert overall == {"accuracy": pytest.approx(0.7), "n_correct": 14, "n_total": 20}


def test_score_clusters_breaks_accuracy_ties_by_the_larger_cluster():
    """A two-council cluster must not outrank a two-hundred-council one on a tie."""
    labels = np.array([0] * 2 + [1] * 20)
    changes = [1, 1] + [0] * 20          # cluster 0 (high change) 100%, cluster 1 100%
    matrix = np.vstack([np.zeros((2, N_FEATURES)), np.ones((20, N_FEATURES))])
    summaries = stats.cluster_summaries(labels, changes, matrix)
    high = stats.mark_high_change_cluster(summaries)

    stats.score_clusters(summaries, labels, changes, high)

    assert summaries[0]["accuracy"] == summaries[1]["accuracy"] == 1.0
    assert summaries[1]["accuracy_rank"] == 1   # size 20 wins the tie
    assert summaries[0]["accuracy_rank"] == 2


def test_score_clusters_ranks_are_a_permutation_of_one_to_n():
    labels = np.array([0] * 5 + [1] * 5 + [2] * 5)
    changes = [0, 0, 0, 1, 1] + [1, 1, 1, 1, 0] + [0, 1, 0, 1, 0]
    matrix = np.zeros((15, N_FEATURES))
    summaries = stats.cluster_summaries(labels, changes, matrix)
    high = stats.mark_high_change_cluster(summaries)

    stats.score_clusters(summaries, labels, changes, high)

    assert sorted(s["accuracy_rank"] for s in summaries) == [1, 2, 3]


def test_score_clusters_overall_accuracy_matches_the_per_row_predictions():
    labels = np.array([0] * 7 + [1] * 3)
    changes = [0, 0, 0, 0, 1, 1, 1] + [1, 1, 0]
    matrix = np.zeros((10, N_FEATURES))
    summaries = stats.cluster_summaries(labels, changes, matrix)
    high = stats.mark_high_change_cluster(summaries)

    predictions, overall = stats.score_clusters(summaries, labels, changes, high)

    expected = sum(1 for p, a in zip(predictions, changes) if p == a)
    assert overall["n_correct"] == expected
    assert overall["accuracy"] == pytest.approx(expected / 10)


def test_score_clusters_handles_an_empty_analysis():
    _predictions, overall = stats.score_clusters([], np.array([]), [], None)
    assert overall == {"accuracy": 0.0, "n_correct": 0, "n_total": 0}
