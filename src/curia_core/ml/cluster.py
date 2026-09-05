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

    # find the number of LAD's AKA number of samples in ML parlance
    n_samples = matrix.shape[0]

    # k here represents the numbers of clusters we want the kmeans
    # algorithm to create.
    max_k = min(max(K_RANGE), n_samples - 1)
    candidate_ks = [k for k in K_RANGE if k <= max_k]
    if not candidate_ks:
        candidate_ks = [2]

    best_k = candidate_ks[0]
    best_score = -1.0

    # for each potential k value
    for k in candidate_ks:

        # create the Kmeans clusters with random state and up to 10 attempts
        model = KMeans(n_clusters=k, n_init=10, random_state=42)

        # label and predict the clusters
        labels = model.fit_predict(matrix)
        if len(set(labels)) < 2:
            continue
        try:
            # key section, score the clusters on:
            ## how cohesvie
            ## how seperated
            ## for example ideally the result would be n very clearly visually
            ## tight and distinct groups
            score = silhouette_score(matrix, labels)
        except ValueError:
            continue

        # if we have found the best k update the value
        if score > best_score:
            best_score = score
            best_k = k

    # re run the model with the optimal value of k and return
    final = KMeans(n_clusters=best_k, n_init=10, random_state=42)
    labels = final.fit_predict(matrix)
    return labels, final.cluster_centers_, best_k, "silhouette"
