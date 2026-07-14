"""Run the cross-analysis prediction step locally (REQUIREMENTS_3).

Requires both ML analyses to exist (run tools/test_all.py or run_ml_local.py first).

Usage:
    CURIA_LOCAL=true python tools/run_prediction_local.py
"""

import os
import sys

os.environ.setdefault("CURIA_LOCAL", "true")
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from curia_core.common import io  # noqa: E402
from curia_core.ml import predict  # noqa: E402


def main():
    analysis_keys = [k for k in io.list_output_keys("analysis/") if k.endswith(".json")]
    items = [{"analysis_key": k} for k in analysis_keys]
    result = predict.run(items)
    print(f"common key_indices ({len(result['key_indices'])}): {result['key_indices']}")
    for r in result["results"]:
        print(
            f"  {r['analysis_key']}: common held-out={r['holdout_accuracy']:.3f} "
            f"per-year held-out={r['per_year_holdout_accuracy']:.3f}"
        )


if __name__ == "__main__":
    main()
