"""Build and normalize the KMeans feature matrix.

Clusters on the 16 rank+decile deltas (ML_FEATURE_KEYS), z-score normalized. The
per-constituency display block keeps the 8 decile deltas (DECILE_DELTA_KEYS).
"""

import numpy as np
from sklearn.decomposition import PCA
from curia_core.common.schemas import DECILE_DELTA_KEYS, ML_FEATURE_KEYS


def build_feature_matrix(entries):
    """Return ``(X, rows)`` where X is an (n, len(ML_FEATURE_KEYS)) float array and
    ``rows`` carries the display metadata per constituency, aligned with X.
    """
    matrix = []
    rows = []
    for entry in entries:
        deprivation = entry["deprivation"]
        # for each LAD for each deprivation delta and decile delta key/value
        # in the order of the machine learning feature keys (the indices we care 
        # about) transform into a feature vector EG Hammersmith&Fulham [15.1, 10.2 ...]
        # where the values are the transformed data
        vector = [float(deprivation[k]) for k in ML_FEATURE_KEYS]
        matrix.append(vector)
        results = entry["local_election_results"]
        rows.append(
            {
                "Local Authority District name": entry["Local Authority District name"],
                "council": results.get("council", ""),
                "change_factor": int(results["change_factor"]),
                "deprivation_deciles": {
                    k: int(deprivation[k]) for k in DECILE_DELTA_KEYS
                },
            }
        )
    return np.asarray(matrix, dtype=float), rows


# A feature whose modal value covers at least this fraction of rows carries no usable
# spread. Eight of the sixteen deltas are decile deltas that almost all round to zero -
# the Income decile delta has exactly ONE non-zero council out of 312 - and z-scoring such
# a column turns that single row into a |z| ~ 17 outlier that then dominates every KMeans
# distance. Treat those columns as degenerate instead of amplifying them.
NEAR_CONSTANT_MODAL_FRACTION = 0.95


def degenerate_feature_mask(matrix):
    """Boolean mask of columns with no usable variation (constant or near-constant)."""
    n_rows = matrix.shape[0]
    if n_rows == 0:
        return np.zeros(matrix.shape[1], dtype=bool)
    modal_fraction = np.array(
        [np.unique(col, return_counts=True)[1].max() / n_rows for col in matrix.T]
    )
    return (matrix.std(axis=0) == 0) | (modal_fraction >= NEAR_CONSTANT_MODAL_FRACTION)


def zscore_normalize(matrix):
    """Z-score each column; degenerate columns become all zeros.

    Zero-variance columns would divide by zero; near-constant columns would survive that
    guard but blow their handful of non-modal rows up into extreme z-scores. Both are
    zeroed, which keeps the column (and so the feature order, centroid keys and
    feature_importance block) while removing its influence on distance.
    """
    degenerate = degenerate_feature_mask(matrix)
    mean = matrix.mean(axis=0)
    std = matrix.std(axis=0)
    safe_std = np.where(degenerate, 1.0, std)
    normalized = (matrix - mean) / safe_std
    normalized[:, degenerate] = 0.0  # explicit: (x - mean) is non-zero when std > 0
    return normalized


def pca_2d(normalized):
    """Project the normalized feature matrix onto 2 principal components for plotting.

    Returns an (n, 2) array. Used purely for the UI cluster scatter (REQUIREMENTS_2 UI-1),
    so clusters separate visually in 2D.
    """

    n_components = min(2, normalized.shape[1], normalized.shape[0])
    coords = PCA(n_components=n_components, random_state=42).fit_transform(normalized)
    if coords.shape[1] < 2:  # pad to 2 columns for degenerate inputs
        coords = np.hstack([coords, np.zeros((coords.shape[0], 2 - coords.shape[1]))])
    return coords
