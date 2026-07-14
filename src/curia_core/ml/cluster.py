"""KMeans with silhouette-based k selection (REQ ML-4).

Runs KMeans for k in 2..7, computes silhouette per k, picks the best k, and refits.
"""

from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score

K_RANGE = range(2, 15)  # 2..7 inclusive


def select_k_and_fit(matrix):
    """Return ``(labels, centroids, best_k, method)``.

    ``matrix`` is the normalized (n, 8) feature array. k is capped at n-1. Falls back to
    k=2 if silhouette can't be computed (e.g. degenerate data).
    """
    n_samples = matrix.shape[0]
    max_k = min(max(K_RANGE), n_samples - 1)
    candidate_ks = [k for k in K_RANGE if k <= max_k]
    if not candidate_ks:
        candidate_ks = [2]

    best_k = candidate_ks[0]
    best_score = -1.0
    for k in candidate_ks:
        model = KMeans(n_clusters=k, n_init=10, random_state=42)
        labels = model.fit_predict(matrix)
        if len(set(labels)) < 2:
            continue
        try:
            score = silhouette_score(matrix, labels)
        except ValueError:
            continue
        if score > best_score:
            best_score = score
            best_k = k

    final = KMeans(n_clusters=best_k, n_init=10, random_state=42)
    labels = final.fit_predict(matrix)
    return labels, final.cluster_centers_, best_k, "silhouette"
