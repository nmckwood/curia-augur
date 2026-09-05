"""Tests for curia_core.ml.cluster — silhouette-based k selection and the KMeans refit."""

import numpy as np
import pytest

from curia_core.ml import cluster, features


def _blobs(n_blobs, per_blob=20, spread=0.1, seed=0):
    rng = np.random.RandomState(seed)
    return np.vstack(
        [rng.normal(i * 10, spread, size=(per_blob, 6)) for i in range(n_blobs)]
    )


def test_select_k_finds_two_well_separated_blobs():
    labels, centroids, best_k, method = cluster.select_k_and_fit(
        features.zscore_normalize(_blobs(2))
    )

    assert best_k == 2
    assert method == "silhouette"
    assert centroids.shape == (2, 6)
    assert set(labels.tolist()) == {0, 1}


def test_select_k_finds_four_well_separated_blobs():
    _labels, _centroids, best_k, _method = cluster.select_k_and_fit(
        features.zscore_normalize(_blobs(4))
    )
    assert best_k == 4


def test_labels_are_returned_one_per_row():
    matrix = features.zscore_normalize(_blobs(3, per_blob=15))
    labels, _centroids, best_k, _ = cluster.select_k_and_fit(matrix)

    assert labels.shape == (45,)
    assert len(set(labels.tolist())) == best_k


def test_k_is_capped_at_n_minus_one_for_tiny_inputs():
    """With 3 rows, k must not exceed 2 or KMeans would raise."""
    matrix = np.array([[0.0, 0.0], [1.0, 1.0], [10.0, 10.0]])

    labels, _centroids, best_k, _ = cluster.select_k_and_fit(matrix)

    assert best_k <= 2
    assert labels.shape == (3,)


@pytest.mark.filterwarnings("ignore::UserWarning")
def test_degenerate_all_zero_input_falls_back_to_k_two():
    """Every row identical: silhouette is undefined, so the documented fallback applies."""
    matrix = np.zeros((10, 4))

    labels, _centroids, best_k, method = cluster.select_k_and_fit(matrix)

    assert best_k == 2
    assert method == "silhouette"
    assert labels.shape == (10,)


def test_selection_is_deterministic_across_runs():
    """random_state is pinned, so repeated runs must not reshuffle clusters."""
    matrix = features.zscore_normalize(_blobs(3))

    first = cluster.select_k_and_fit(matrix)
    second = cluster.select_k_and_fit(matrix)

    assert first[2] == second[2]
    assert np.array_equal(first[0], second[0])


def test_k_range_starts_at_two():
    assert min(cluster.K_RANGE) == 2


@pytest.mark.parametrize("n_blobs", [2, 3, 5])
def test_best_k_always_lands_inside_the_configured_range(n_blobs):
    matrix = features.zscore_normalize(_blobs(n_blobs))
    _labels, _centroids, best_k, _ = cluster.select_k_and_fit(matrix)
    assert best_k in cluster.K_RANGE
