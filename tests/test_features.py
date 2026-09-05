"""Tests for curia_core.ml.features — feature-matrix construction, the degenerate-column
guard, z-score normalization and the 2D PCA projection."""

import numpy as np
import pytest

from curia_core.common.schemas import DECILE_DELTA_KEYS, ML_FEATURE_KEYS
from curia_core.ml import features
from tests.conftest import ingestion_entry


# --- build_feature_matrix ----------------------------------------------------


def test_build_feature_matrix_shape_and_column_order():
    entries = [
        ingestion_entry("Alpha", change_factor=1),
        ingestion_entry("Bravo", change_factor=0),
    ]

    matrix, rows = features.build_feature_matrix(entries)

    assert matrix.shape == (2, len(ML_FEATURE_KEYS))
    assert matrix.dtype == float
    # Column i must be feature key i, for every row.
    for i, key in enumerate(ML_FEATURE_KEYS):
        assert matrix[0, i] == pytest.approx(float(entries[0]["deprivation"][key]))


def test_build_feature_matrix_carries_display_metadata_aligned_with_the_rows():
    entries = [
        ingestion_entry("Alpha", change_factor=1, council="Alpha CC"),
        ingestion_entry("Bravo", change_factor=0, council="Bravo CC"),
    ]

    _matrix, rows = features.build_feature_matrix(entries)

    assert [r["Local Authority District name"] for r in rows] == ["Alpha", "Bravo"]
    assert [r["council"] for r in rows] == ["Alpha CC", "Bravo CC"]
    assert [r["change_factor"] for r in rows] == [1, 0]
    assert set(rows[0]["deprivation_deciles"]) == set(DECILE_DELTA_KEYS)


def test_build_feature_matrix_defaults_a_missing_council_to_empty_string():
    entry = ingestion_entry("Alpha", change_factor=0)
    del entry["local_election_results"]["council"]

    _matrix, rows = features.build_feature_matrix([entry])

    assert rows[0]["council"] == ""


def test_build_feature_matrix_raises_when_a_feature_key_is_missing():
    """A silently-defaulted feature would corrupt the distance metric, so it must fail."""
    entry = ingestion_entry("Alpha", change_factor=0)
    del entry["deprivation"][ML_FEATURE_KEYS[0]]

    with pytest.raises(KeyError):
        features.build_feature_matrix([entry])


def test_build_feature_matrix_of_no_entries_is_empty():
    matrix, rows = features.build_feature_matrix([])
    assert matrix.size == 0
    assert rows == []


# --- degenerate_feature_mask -------------------------------------------------


def test_degenerate_mask_flags_constant_and_near_constant_columns():
    matrix = np.zeros((100, 3))
    matrix[0, 0] = 5.0             # near-constant: 99 of 100 identical
    matrix[:, 1] = np.arange(100)  # well spread
    matrix[:, 2] = 7.0             # exactly constant

    mask = features.degenerate_feature_mask(matrix)

    assert mask.tolist() == [True, False, True]


def test_degenerate_mask_uses_the_documented_modal_fraction_threshold():
    n = 100
    threshold = features.NEAR_CONSTANT_MODAL_FRACTION  # 0.95

    just_under = np.arange(n, dtype=float)
    just_under[: int(n * threshold) - 1] = 0.0   # 94% modal -> keep
    just_over = np.arange(n, dtype=float)
    just_over[: int(n * threshold)] = 0.0        # 95% modal -> drop

    assert features.degenerate_feature_mask(just_under.reshape(n, 1))[0] is np.False_
    assert features.degenerate_feature_mask(just_over.reshape(n, 1))[0] is np.True_


def test_degenerate_mask_of_an_empty_matrix_is_all_false():
    mask = features.degenerate_feature_mask(np.zeros((0, 4)))
    assert mask.shape == (4,)
    assert not mask.any()


# --- zscore_normalize --------------------------------------------------------


def test_zscore_normalize_centres_and_scales_a_healthy_column():
    matrix = np.arange(100, dtype=float).reshape(100, 1)

    normalized = features.zscore_normalize(matrix)

    assert float(normalized.mean()) == pytest.approx(0.0, abs=1e-9)
    assert float(normalized.std()) == pytest.approx(1.0)


def test_zscore_normalize_zeroes_degenerate_columns_instead_of_amplifying_them():
    """A single non-modal row in a near-constant column would z-score to |z| ~ 10 and
    dominate every KMeans distance."""
    matrix = np.zeros((100, 3))
    matrix[0, 0] = 5.0
    matrix[:, 1] = np.arange(100)
    matrix[:, 2] = 7.0

    normalized = features.zscore_normalize(matrix)

    assert np.all(normalized[:, 0] == 0.0)
    assert np.all(normalized[:, 2] == 0.0)
    assert np.abs(normalized[:, 1]).max() > 1.0


def test_zscore_normalize_preserves_shape_so_feature_order_survives():
    matrix = np.random.RandomState(0).normal(size=(20, len(ML_FEATURE_KEYS)))
    assert features.zscore_normalize(matrix).shape == matrix.shape


def test_zscore_normalize_never_divides_by_zero():
    matrix = np.full((10, 2), 3.0)
    normalized = features.zscore_normalize(matrix)
    assert np.isfinite(normalized).all()


# --- pca_2d ------------------------------------------------------------------


def test_pca_2d_returns_two_columns_per_row():
    matrix = np.random.RandomState(0).normal(size=(30, 8))
    coords = features.pca_2d(features.zscore_normalize(matrix))
    assert coords.shape == (30, 2)


def test_pca_2d_pads_to_two_columns_for_single_feature_input():
    """Degenerate inputs must still give the UI scatter an (n, 2) array."""
    matrix = np.arange(10, dtype=float).reshape(10, 1)
    coords = features.pca_2d(matrix)

    assert coords.shape == (10, 2)
    assert np.all(coords[:, 1] == 0.0)


def test_pca_2d_separates_two_well_defined_blobs():
    rng = np.random.RandomState(0)
    matrix = np.vstack(
        [rng.normal(0, 0.1, size=(20, 6)), rng.normal(8, 0.1, size=(20, 6))]
    )
    coords = features.pca_2d(features.zscore_normalize(matrix))

    # The blob means must be far apart on the first component.
    assert abs(coords[:20, 0].mean() - coords[20:, 0].mean()) > 1.0
