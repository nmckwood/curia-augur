"""End-to-end local pipeline test (REQ General-12).

Imports each relevant module and runs them sequentially as if in AWS: ingestion then ML,
for both comparison pairs, validating both JSON outputs against the REQUIREMENTS schemas.

Run:
    CURIA_LOCAL=true python tools/test_all.py
"""

import json
import os
import sys

os.environ.setdefault("CURIA_LOCAL", "true")
_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(_REPO_ROOT, "src"))
sys.path.insert(0, _REPO_ROOT)

from curia_core.common import io  # noqa: E402
from curia_core.common.schemas import (  # noqa: E402
    ingestion_output_schema,
    ml_output_schema,
)
from curia_core.ingestion import pipeline as ingestion_pipeline  # noqa: E402
from curia_core.ml import pipeline as ml_pipeline  # noqa: E402
from curia_core.ml import predict as ml_predict  # noqa: E402
from tools.run_ingestion_local import PAIRS  # noqa: E402


def _check(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"  ok: {message}")


def run_pair(name, event):
    print(f"\n=== pair {name}: ingestion ===")
    ingest = ingestion_pipeline.run(event)
    print(f"  {ingest}")
    _check(ingest["n_entries"] > 250, "ingestion produced > 250 joined LADs")

    entries = json.loads(io.read_output_text(ingest["output_key"]))
    _check(
        not io.validation_errors(entries, ingestion_output_schema()),
        "ingestion output validates against schema",
    )
    _check(
        all(e["local_election_results"]["change_factor"] in (0, 1) for e in entries),
        "all change_factor values are binary majority-flip (0 or 1)",
    )
    unused = _read_local(ingest["output_log"])
    _check(len(unused.strip()) > 0, "unused log is non-empty and readable")

    print(f"=== pair {name}: ml ===")
    analysis_result = ml_pipeline.run({"output_key": ingest["output_key"]})
    print(f"  {analysis_result}")
    analysis = json.loads(io.read_output_text(analysis_result["analysis_key"]))
    _check(
        not io.validation_errors(analysis, ml_output_schema()),
        "ML output validates against schema",
    )
    _check(2 <= analysis["meta"]["k"] <= 14, "best k in [2, 14]")
    _check("p_value" in analysis["significance_test"], "Kruskal-Wallis p_value present")
    _check(
        analysis["feature_importance"][0]["rank"] == 1,
        "feature_importance is ranked",
    )
    _check(
        any(c["is_high_change_cluster"] for c in analysis["clusters"]),
        "a high-change cluster is flagged",
    )
    _check(
        all("pca_x" in c and "pca_y" in c for c in analysis["constituencies"]),
        "every constituency has pca_x/pca_y coords",
    )
    # REQUIREMENTS_4: the clustering scored as a prediction.
    high_ids = {c["cluster_id"] for c in analysis["clusters"] if c["is_high_change_cluster"]}
    _check(
        all(
            c["change_factor_cluster"] == (1 if c["cluster_id"] in high_ids else 0)
            for c in analysis["constituencies"]
        ),
        "change_factor_cluster is 1 exactly in the high-change cluster",
    )
    _check(
        sorted(c["accuracy_rank"] for c in analysis["clusters"])
        == list(range(1, len(analysis["clusters"]) + 1)),
        "clusters are ranked 1..n by accuracy",
    )
    overall = analysis["meta"]["cluster_accuracy"]
    actual_correct = sum(
        1
        for c in analysis["constituencies"]
        if c["change_factor_cluster"] == c["change_factor"]
    )
    _check(
        overall["n_correct"] == actual_correct
        and overall["n_total"] == len(analysis["constituencies"]),
        f"meta.cluster_accuracy matches the constituencies "
        f"({overall['accuracy'] * 100:.1f}%)",
    )
    return {
        "analysis_key": analysis_result["analysis_key"],
        "ingestion_key": ingest["output_key"],
    }


def _read_local(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def run_prediction(items):
    print("\n=== cross-analysis prediction (REQUIREMENTS_3) ===")
    result = ml_predict.run(items)
    print(f"  key_indices: {result['key_indices']}")
    _check(len(result["key_indices"]) > 0, "common key_indices is non-empty")
    for item, res in zip(items, result["results"]):
        print(
            f"  {res['analysis_key']}: common held-out={res['holdout_accuracy']:.3f} "
            f"per-year held-out={res['per_year_holdout_accuracy']:.3f}"
        )
        analysis = json.loads(io.read_output_text(item["analysis_key"]))
        _check(
            not io.validation_errors(analysis, ml_output_schema()),
            f"{res['analysis_key']} still validates after prediction",
        )
        _check(
            all(
                c.get("change_factor_deprivation_key_indices") in (0, 1)
                for c in analysis["constituencies"]
            ),
            f"{res['analysis_key']} has binary predicted change_factor_deprivation_key_indices",
        )
        _check(
            analysis["meta"].get("key_indices"),
            f"{res['analysis_key']} meta.key_indices populated",
        )


def main():
    items = [run_pair(name, event) for name, event in PAIRS.items()]
    run_prediction(items)
    print("\nALL END-TO-END CHECKS PASSED")


if __name__ == "__main__":
    main()
