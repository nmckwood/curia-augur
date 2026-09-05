"""Cross-analysis prediction step (REQUIREMENTS_3).

After both comparison-pair ML analyses exist, join them to find the deprivation indices
that COMMONLY drive electoral change, then use only those to predict each constituency's
majority-flip change_factor and compare against the actual outcome.

Validity notes:
- Index selection AND model fitting happen on a stratified TRAIN split only, so the
  held-out accuracy (measured on the unseen TEST split) has no feature-selection leakage.
- We report two held-out numbers per analysis: the COMMON-indices model (the REQ_3
  requirement, which drives the per-constituency field + UI maps) and a PER-YEAR
  best-indices benchmark (each analysis's own top indices), so the cost of insisting on
  common drivers is visible.
- Per-year "best indices" are the top-K of the 16 deprivation deltas ranked by absolute
  standardized logistic-regression coefficient, fit on the train split.
"""

import json

from curia_core.common import io
from curia_core.common.schemas import ML_FEATURE_KEYS

# training data, 70% will be for training and 30% for verification
TEST_SIZE = 0.3
# common random seed number
RANDOM_STATE = 42


def common_indices(top_lists):
    """Ordered intersection of per-analysis top-index lists.

    Preserves the first list's order. Falls back to the union of each list's best index
    when the intersection is empty (so there is always something to predict with).
    """
    if not top_lists:
        return []
    common = set(top_lists[0])
    for names in top_lists[1:]:
        common &= set(names)
    if common:
        return [name for name in top_lists[0] if name in common]
    fallback = []
    for names in top_lists:
        if names and names[0] not in fallback:
            fallback.append(names[0])
    return fallback


def _build_matrix(analysis, ingestion_entries):
    """Return (constituencies, X16, y): the full 16-delta feature matrix (aligned to the
    analysis constituencies by LAD name) and the actual change_factor targets."""
    import numpy as np

    deltas_by_lad = {
        e["Local Authority District name"]: e["deprivation"] for e in ingestion_entries
    }
    cons = analysis["constituencies"]
    matrix = np.array(
        [
            [
                float(deltas_by_lad.get(c["Local Authority District name"], {}).get(idx, 0))
                for idx in ML_FEATURE_KEYS
            ]
            for c in cons
        ],
        dtype=float,
    )
    targets = np.array([int(c["change_factor"]) for c in cons], dtype=int)
    return cons, matrix, targets


def _split(targets):
    """Stratified train/test index split. Returns (train_idx, test_idx).

    Degenerate cases (fewer than 4 rows, a single class, or a class with <2 members) can't
    be held out cleanly, so both indices span all rows and accuracy is in-sample.
    """
    import numpy as np

    n = len(targets)
    idx = np.arange(n)
    classes = sorted(set(targets.tolist()))
    counts = [int((targets == c).sum()) for c in classes]
    if n < 4 or len(classes) < 2 or min(counts) < 2:
        return idx, idx

    from sklearn.model_selection import train_test_split

    return train_test_split(
        idx, test_size=TEST_SIZE, random_state=RANDOM_STATE, stratify=targets
    )


def _rank_indices_by_coef(matrix, targets, train_idx, k):
    """Top-k feature names by |standardized logistic coefficient|, fit on the train split.

    Falls back to the first k feature names if the train split has a single class.
    """
    import numpy as np

    train_targets = targets[train_idx]
    if len(set(train_targets.tolist())) < 2:
        return list(ML_FEATURE_KEYS[:k])

    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler

    scaler = StandardScaler().fit(matrix[train_idx])
    model = LogisticRegression(max_iter=1000).fit(
        scaler.transform(matrix[train_idx]), train_targets
    )
    order = np.argsort(np.abs(model.coef_[0]))[::-1]
    return [ML_FEATURE_KEYS[i] for i in order[:k]]


def _fit_eval(matrix, targets, train_idx, test_idx):
    """Fit LogisticRegression on the train split, predict ALL rows, and score train/test.

    Returns (predictions, metrics). Single-class train split -> majority-class prediction.
    """
    import numpy as np

    train_targets = targets[train_idx]
    if len(set(train_targets.tolist())) < 2:
        only = int(train_targets[0]) if len(train_targets) else 0
        preds = np.full(len(targets), only, dtype=int)
    else:
        from sklearn.linear_model import LogisticRegression
        from sklearn.preprocessing import StandardScaler

        scaler = StandardScaler().fit(matrix[train_idx])
        scaled = scaler.transform(matrix)
        model = LogisticRegression(max_iter=1000).fit(scaled[train_idx], train_targets)
        preds = model.predict(scaled)

    def accuracy(indices):
        return float((preds[indices] == targets[indices]).mean()) if len(indices) else 0.0

    return [int(v) for v in preds], {
        "holdout_accuracy": accuracy(test_idx),
        "train_accuracy": accuracy(train_idx),
    }


def _majority_baseline(targets, train_idx, test_idx):
    """The "no machine learning at all" bar: always predict the most common change_factor.

    This is the bar any index must beat: if the majority of councils don't flip, a model
    that predicts "no change" for everyone already scores the base rate. Reported two ways
    so it is comparable to both other numbers in the UI - ``holdout_accuracy`` against the
    regression model's held-out score, and ``all_accuracy`` against the cluster prediction,
    which is scored over every authority.
    """
    import numpy as np

    train_targets = targets[train_idx]
    if len(train_targets) == 0:
        return {
            "majority_class": 0,
            "holdout_accuracy": 0.0,
            "all_accuracy": 0.0,
            "n_correct_all": 0,
            "n_total_all": int(len(targets)),
        }
    values, counts = np.unique(train_targets, return_counts=True)
    majority = int(values[counts.argmax()])
    n_correct_all = int((targets == majority).sum())
    return {
        "majority_class": majority,
        "holdout_accuracy": (
            float((targets[test_idx] == majority).mean()) if len(test_idx) else 0.0
        ),
        "all_accuracy": float(n_correct_all / len(targets)) if len(targets) else 0.0,
        "n_correct_all": n_correct_all,
        "n_total_all": int(len(targets)),
    }


def _univariate_accuracies(matrix, targets, train_idx, test_idx):
    """Held-out accuracy of a single-feature model per deprivation index (train-fit).

    Answers "which individual indices are most predictive of change this year". Returns a
    list of ``{feature, holdout_accuracy, rank}`` sorted by held-out accuracy descending.
    """
    details = []
    for i, name in enumerate(ML_FEATURE_KEYS):
        _preds, metrics = _fit_eval(matrix[:, [i]], targets, train_idx, test_idx)
        details.append(
            {"feature": name, "holdout_accuracy": metrics["holdout_accuracy"]}
        )
    details.sort(key=lambda d: d["holdout_accuracy"], reverse=True)
    for rank, detail in enumerate(details, start=1):
        detail["rank"] = rank
    return details


def _ingestion_key_for(analysis_key):
    """Map analysis/analysis-<key>.json -> output/deprivation-election-data-<key>.json."""
    name = analysis_key.split("/")[-1]
    composite = name[len("analysis-"):-len(".json")]
    return f"output/deprivation-election-data-{composite}.json"


def run(items, top_k=8):
    """Run the prediction join over multiple analyses.

    ``items`` is a list of ``{"analysis_key": ..., "ingestion_key": ...}`` (ingestion_key
    derived from analysis_key when absent). Selects indices on each analysis's train split,
    computes the common (intersection) index set, fits both a common-indices model and a
    per-year best-indices benchmark, augments + writes back each analysis, returns a summary.
    """
    # for some set of values X (deprivation data) cam we predict Y (the change factor)

    # prepare the data pipeline and machine learning pipeline data for supervised learning
    loaded = []
    for item in items:
        analysis_key = item["analysis_key"]
        ingestion_key = item.get("ingestion_key") or _ingestion_key_for(analysis_key)
        analysis = json.loads(io.read_output_text(analysis_key))
        entries = json.loads(io.read_output_text(ingestion_key))
        loaded.append((analysis_key, analysis, entries))

    prepared = []
    for analysis_key, analysis, entries in loaded:
        cons, matrix, targets = _build_matrix(analysis, entries)
        train_idx, test_idx = _split(targets)
        per_year = _rank_indices_by_coef(matrix, targets, train_idx, top_k)
        prepared.append(
            {
                "analysis_key": analysis_key,
                "analysis": analysis,
                "constituencies": cons,
                "matrix": matrix,
                "targets": targets,
                "train_idx": train_idx,
                "test_idx": test_idx,
                "per_year": per_year,
            }
        )

    # for each of our comparison years find the common X values I.E the indices of deprivation
    # which are ranked highly in both data sets
    common = common_indices([p["per_year"] for p in prepared])

    results = []
    # for each compared election year
    for p in prepared:
        # extract only the indices which are common EG use columns a and b in the analysis
        common_cols = [ML_FEATURE_KEYS.index(i) for i in common]
        per_year_cols = [ML_FEATURE_KEYS.index(i) for i in p["per_year"]]

        # for each set of common indices for each local authority train the model on the
        # combinations (for each LAD) and the answer they result in (change factor),
        # then the model makes predications based on that and verifies against its test 
        # data set, essentially assigning a score to each predictions that fit answers
        preds_common, common_metrics = _fit_eval(
            p["matrix"][:, common_cols], p["targets"], p["train_idx"], p["test_idx"]
        )
        preds_per_year, per_year_metrics = _fit_eval(
            p["matrix"][:, per_year_cols], p["targets"], p["train_idx"], p["test_idx"]
        )
        # we repeat the _fit_eval but individually for each deprivation indices to collect
        # additional data to see if they are more informative than the cluster of common
        # indices.
        index_details = _univariate_accuracies(
            p["matrix"], p["targets"], p["train_idx"], p["test_idx"]
        )

        # now without using the model we find the most common result in the training data
        # I.E what is the most common change_factor (0 or 1), then compare against each of
        # our test sets predicted results, does our regression model predict change more than
        # simply picking the most common result
        baseline = _majority_baseline(p["targets"], p["train_idx"], p["test_idx"])

        # prepare the output data
        for c, pred_common, pred_py in zip(
            p["constituencies"], preds_common, preds_per_year
        ):
            c["change_factor_deprivation_key_indices"] = int(pred_common)
            c["change_factor_per_year_key_indices"] = int(pred_py)

        meta = p["analysis"].setdefault("meta", {})
        meta["key_indices"] = list(common)
        meta["prediction"] = {
            "method": "logistic-regression",
            "train_size": int(len(p["train_idx"])),
            "test_size": int(len(p["test_idx"])),
            "holdout_accuracy": common_metrics["holdout_accuracy"],
            "train_accuracy": common_metrics["train_accuracy"],
            "baseline_accuracy": baseline["holdout_accuracy"],
            "baseline": baseline,
            "per_year_holdout_accuracy": per_year_metrics["holdout_accuracy"],
            "per_year_train_accuracy": per_year_metrics["train_accuracy"],
            "per_year_indices": list(p["per_year"]),
            "per_year_index_details": index_details,
        }
        io.write_output_json(p["analysis_key"], p["analysis"])
        results.append(
            {
                "analysis_key": p["analysis_key"],
                "holdout_accuracy": common_metrics["holdout_accuracy"],
                "per_year_holdout_accuracy": per_year_metrics["holdout_accuracy"],
            }
        )

    return {"key_indices": common, "results": results}
