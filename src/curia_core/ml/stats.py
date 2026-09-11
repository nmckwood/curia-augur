"""Cluster statistics: per-cluster change_factor, feature importance.

REQ ML-5 (which deprivation indices characterize the high-change cluster - the features
with the largest deviation of the high-change cluster mean from the other clusters) and
REQUIREMENTS_4 (score each cluster's implied prediction against the actual outcome).
"""

import numpy as np

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


def cluster_predictions(labels, high_change_cluster_id):
    """The change_factor_cluster of every row: 1 in the high-change cluster, else 0.

    This is the clustering's own prediction - k-means only sees deprivation data, so the
    single high-change cluster is the group it says should flip (REQUIREMENTS_4 ML-1).
    """
    return [1 if int(label) == high_change_cluster_id else 0 for label in labels]


def score_clusters(summaries, labels, change_factors, high_change_cluster_id):
    """Score each cluster's prediction against the actual outcome and rank by accuracy.

    A cluster predicts 1 for all its members if it is the high-change cluster and 0
    otherwise, so its accuracy is the percentage of its councils whose actual
    change_factor matched that call. Mutates ``summaries`` in place and returns the
    overall (all-council) accuracy block (REQUIREMENTS_4 General).
    """
    predictions = cluster_predictions(labels, high_change_cluster_id)
    actuals = [int(round(float(c))) for c in change_factors]

    for summary in summaries:
        cluster_id = summary["cluster_id"]
        pairs = [
            (p, a)
            for label, p, a in zip(labels, predictions, actuals)
            if int(label) == cluster_id
        ]
        correct = sum(1 for p, a in pairs if p == a)
        summary["predicted_change_factor"] = 1 if cluster_id == high_change_cluster_id else 0
        summary["n_correct"] = int(correct)
        summary["accuracy"] = float(correct / len(pairs)) if pairs else 0.0

    # Rank 1 = most accurate cluster. Ties broken by the larger cluster first, so a rank
    # is never awarded to a two-council cluster over a two-hundred-council one.
    for rank, summary in enumerate(
        sorted(summaries, key=lambda s: (-s["accuracy"], -s["size"], s["cluster_id"])),
        start=1,
    ):
        summary["accuracy_rank"] = rank

    total = len(actuals)
    overall = sum(1 for p, a in zip(predictions, actuals) if p == a)
    return predictions, {
        "accuracy": float(overall / total) if total else 0.0,
        "n_correct": int(overall),
        "n_total": int(total),
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
