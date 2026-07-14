"""Build and normalize the KMeans feature matrix.

Clusters on the 16 rank+decile deltas (ML_FEATURE_KEYS), z-score normalized. The
per-constituency display block keeps the 8 decile deltas (DECILE_DELTA_KEYS).
"""

import numpy as np

from curia_core.common.schemas import DECILE_DELTA_KEYS, ML_FEATURE_KEYS


def build_feature_matrix(entries):
    """Return ``(X, rows)`` where X is an (n, len(ML_FEATURE_KEYS)) float array and
    ``rows`` carries the display metadata per constituency, aligned with X.
    """
    matrix = []
    rows = []
    for entry in entries:
        deprivation = entry["deprivation"]
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


def zscore_normalize(matrix):
    """Z-score each column; zero-variance columns become all zeros (avoid div-by-0)."""
    mean = matrix.mean(axis=0)
    std = matrix.std(axis=0)
    safe_std = np.where(std == 0, 1.0, std)
    return (matrix - mean) / safe_std


def pca_2d(normalized):
    """Project the normalized feature matrix onto 2 principal components for plotting.

    Returns an (n, 2) array. Used purely for the UI cluster scatter (REQUIREMENTS_2 UI-1),
    so clusters separate visually in 2D.
    """
    from sklearn.decomposition import PCA

    n_components = min(2, normalized.shape[1], normalized.shape[0])
    coords = PCA(n_components=n_components, random_state=42).fit_transform(normalized)
    if coords.shape[1] < 2:  # pad to 2 columns for degenerate inputs
        coords = np.hstack([coords, np.zeros((coords.shape[0], 2 - coords.shape[1]))])
    return coords
