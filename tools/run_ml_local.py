"""Run the ML pipeline locally against an ingestion output file in ./local_output.

Usage:
    CURIA_LOCAL=true python tools/run_ml_local.py [output_key]

Defaults to running both comparison-pair outputs produced by run_ingestion_local.py.
"""

import os
import sys

os.environ.setdefault("CURIA_LOCAL", "true")
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from curia_core.ml import pipeline  # noqa: E402

DEFAULT_KEYS = [
    "output/deprivation-election-data-d_2015_d_2019_le_2018_le_2022.json",
    "output/deprivation-election-data-d_2019_d_2025_le_2022_le_2026.json",
]


def main():
    keys = sys.argv[1:] or DEFAULT_KEYS
    for key in keys:
        result = pipeline.run({"output_key": key})
        print(f"{key}: {result}")


if __name__ == "__main__":
    main()
