"""Unit tests for the Curia Augur functional core.

Run: ./.venv/bin/python -m unittest tests.test_core -v
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import numpy as np  # noqa: E402

from curia_core.ingestion import deprivation, election, joining  # noqa: E402
from curia_core.ml import features, cluster, stats, predict  # noqa: E402


class ElectionTests(unittest.TestCase):
    def test_change_factor_majority_flip(self):
        # Benchmark majority Labour (3 Lab, 2 Con); target majority Conservative.
        benchmark = [
            {"Council": "Anytown", "Party Name": "Labour"},
            {"Council": "Anytown", "Party Name": "Labour"},
            {"Council": "Anytown", "Party Name": "Labour"},
            {"Council": "Anytown", "Party Name": "Conservative"},
            {"Council": "Anytown", "Party Name": "Conservative"},
        ]
        target = [
            {"Council": "Anytown", "Party Name": "Conservative"},
            {"Council": "Anytown", "Party Name": "Conservative"},
            {"Council": "Anytown", "Party Name": "Conservative"},
            {"Council": "Anytown", "Party Name": "Labour"},
            {"Council": "Anytown", "Party Name": "Labour"},
        ]
        result = election.build_election_results(benchmark, target)["Anytown"]
        self.assertEqual(result["change_factor"], 1)  # majority flipped
        self.assertEqual(result["Conservative"], 1)
        self.assertEqual(result["Labour"], -1)

    def test_change_factor_no_flip(self):
        # Labour stays the majority in both years -> no change.
        benchmark = [
            {"Council": "Steadytown", "Party Name": "Labour"},
            {"Council": "Steadytown", "Party Name": "Labour"},
            {"Council": "Steadytown", "Party Name": "Conservative"},
        ]
        target = [
            {"Council": "Steadytown", "Party Name": "Labour"},
            {"Council": "Steadytown", "Party Name": "Labour"},
            {"Council": "Steadytown", "Party Name": "Conservative"},
        ]
        result = election.build_election_results(benchmark, target)["Steadytown"]
        self.assertEqual(result["change_factor"], 0)  # Labour still largest


class DeprivationTests(unittest.TestCase):
    def test_aggregate_and_delta(self):
        from curia_core.common.schemas import decile_field, rank_field, DOMAINS

        def row(lad, value):
            r = {"Local Authority District name (2019)": lad}
            for d in DOMAINS:
                r[rank_field(d)] = value * 100
                r[decile_field(d)] = value
            return r

        start = [row("Foo", 6), row("Foo", 8)]  # mean decile 7
        end = [row("Foo", 4), row("Foo", 4)]    # mean decile 4
        deltas = deprivation.compute_deltas(
            deprivation.aggregate_to_lad(start),
            deprivation.aggregate_to_lad(end),
        )
        key = decile_field("Income") + " delta"
        self.assertEqual(deltas["Foo"][key], 3)  # 7 - 4


class JoiningTests(unittest.TestCase):
    def test_fuzzy_match_and_unmatched(self):
        matches, unmatched = joining.match_councils_to_lads(
            ["Cambridgeshire", "Totally Fictional Place"],
            ["Cambridgeshire", "Norfolk"],
        )
        self.assertEqual(matches["Cambridgeshire"], "Cambridgeshire")
        self.assertTrue(any(u[0] == "Totally Fictional Place" for u in unmatched))


class MlTests(unittest.TestCase):
    def test_zscore_and_kselection(self):
        rng = np.random.RandomState(0)
        cluster_a = rng.normal(0, 0.1, size=(30, 8))
        cluster_b = rng.normal(5, 0.1, size=(30, 8))
        matrix = np.vstack([cluster_a, cluster_b])
        normalized = features.zscore_normalize(matrix)
        self.assertAlmostEqual(float(normalized.mean()), 0.0, places=6)
        labels, _c, best_k, method = cluster.select_k_and_fit(normalized)
        self.assertEqual(best_k, 2)  # two well-separated blobs
        self.assertEqual(method, "silhouette")

    def test_significance_and_importance(self):
        from curia_core.common.schemas import ML_FEATURE_KEYS

        n_features = len(ML_FEATURE_KEYS)
        labels = np.array([0] * 20 + [1] * 20)
        change = [10] * 20 + [80] * 20
        matrix = np.vstack(
            [np.zeros((20, n_features)), np.ones((20, n_features))]
        )
        summaries = stats.cluster_summaries(labels, change, matrix)
        high = stats.mark_high_change_cluster(summaries)
        self.assertEqual(high, 1)
        sig = stats.significance_test(labels, change)
        self.assertTrue(sig["significant"])
        ranked = stats.feature_importance(labels, matrix, high)
        self.assertEqual(ranked[0]["rank"], 1)


class PredictTests(unittest.TestCase):
    def test_common_indices_intersection(self):
        common = predict.common_indices([["A", "B", "C"], ["B", "C", "D"]])
        self.assertEqual(common, ["B", "C"])  # intersection, first-list order

    def test_common_indices_fallback_union(self):
        # No overlap -> union of each list's best (first) index.
        common = predict.common_indices([["A", "B"], ["C", "D"]])
        self.assertEqual(common, ["A", "C"])

    def test_fit_eval_holdout_perfect_separation(self):
        # Feature perfectly separates the classes -> held-out accuracy is 1.0.
        n = 40
        matrix = np.array([[100.0] if i >= n // 2 else [-100.0] for i in range(n)])
        targets = np.array([1 if i >= n // 2 else 0 for i in range(n)])
        train_idx, test_idx = predict._split(targets)
        self.assertGreater(len(test_idx), 0)
        self.assertLess(len(train_idx), n)  # genuine held-out split
        preds, metrics = predict._fit_eval(matrix, targets, train_idx, test_idx)
        self.assertEqual(metrics["holdout_accuracy"], 1.0)
        self.assertTrue(all(p == t for p, t in zip(preds, targets.tolist())))


if __name__ == "__main__":
    unittest.main()
