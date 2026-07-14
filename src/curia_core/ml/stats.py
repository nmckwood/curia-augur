"""Cluster statistics: per-cluster change_factor, Kruskal-Wallis, feature importance.

Implements REQ ML-4 (mean change_factor per cluster, Kruskal-Wallis significance) and
REQ ML-5 (which deprivation indices characterize the high-change cluster - the features
with the largest deviation of the high-change cluster mean from the other clusters).
"""

import numpy as np
from scipy.stats import kruskal

from curia_core.common.schemas import ML_FEATURE_KEYS

ALPHA = 0.05


def cluster_summaries(labels, change_factors, normalized_matrix):
    """Return per-cluster dicts with size, mean/median change_factor and centroid."""
    summaries = []
    change_factors = np.asarray(change_factors, dtype=float)
    for cluster_id in sorted(set(int(c) for c in labels)):
        mask = labels == cluster_id
        cluster_changes = change_factors[mask]
        centroid = normalized_matrix[mask].mean(axis=0)
        summaries.append(
            {
                "cluster_id": int(cluster_id),
                "size": int(mask.sum()),
                "mean_change_factor": float(cluster_changes.mean()),
                "median_change_factor": float(np.median(cluster_changes)),
                "is_high_change_cluster": False,  # set later
                "centroid": {
                    key: float(centroid[i]) for i, key in enumerate(ML_FEATURE_KEYS)
                },
            }
        )
    return summaries


def mark_high_change_cluster(summaries):
    """Flag the cluster with the highest mean change_factor; return its id."""
    if not summaries:
        return None
    high = max(summaries, key=lambda s: s["mean_change_factor"])
    for summary in summaries:
        summary["is_high_change_cluster"] = summary["cluster_id"] == high["cluster_id"]
    return high["cluster_id"]


def significance_test(labels, change_factors):
    """Kruskal-Wallis across clusters' change_factor distributions."""
    change_factors = np.asarray(change_factors, dtype=float)
    groups = [
        change_factors[labels == c] for c in sorted(set(int(x) for x in labels))
    ]
    groups = [g for g in groups if len(g) > 0]
    if len(groups) < 2:
        return {"test": "kruskal-wallis", "statistic": 0.0, "p_value": 1.0, "significant": False}
    statistic, p_value = kruskal(*groups)
    return {
        "test": "kruskal-wallis",
        "statistic": float(statistic),
        "p_value": float(p_value),
        "significant": bool(p_value < ALPHA),
    }


def feature_importance(labels, normalized_matrix, high_change_cluster_id):
    """Rank features by |high-change cluster mean - other clusters mean| (REQ ML-5)."""
    high_mask = labels == high_change_cluster_id
    other_mask = ~high_mask
    ranked = []
    for i, key in enumerate(ML_FEATURE_KEYS):
        high_mean = float(normalized_matrix[high_mask, i].mean()) if high_mask.any() else 0.0
        other_mean = float(normalized_matrix[other_mask, i].mean()) if other_mask.any() else 0.0
        ranked.append(
            {
                "feature": key,
                "high_change_cluster_mean": high_mean,
                "other_clusters_mean": other_mean,
                "deviation_score": abs(high_mean - other_mean),
            }
        )
    ranked.sort(key=lambda r: r["deviation_score"], reverse=True)
    for rank, item in enumerate(ranked, start=1):
        item["rank"] = rank
    return ranked
