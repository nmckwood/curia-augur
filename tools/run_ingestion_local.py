"""Run the data ingestion pipeline locally against the files in ./data.

Usage:
    CURIA_LOCAL=true python tools/run_ingestion_local.py [pair]

``pair`` is 1 (2015->2019 dep, 2018->2022 election) or 2 (2019->2025 dep, 2022->2026
election). Defaults to running both. Outputs land in ./local_output/output/.
"""

import os
import sys

os.environ.setdefault("CURIA_LOCAL", "true")
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from curia_core.ingestion import pipeline  # noqa: E402

PAIRS = {
    "1": {
        "deprivation_file_start": "2015_dep.json",
        "deprivation_file_end": "2019_dep.json",
        "local_election_start": "opencouncildata_councillors_2018.csv",
        "local_election_end": "opencouncildata_councillors_2022.csv",
    },
    "2": {
        "deprivation_file_start": "2019_dep.json",
        "deprivation_file_end": "2025_dep.json",
        "local_election_start": "opencouncildata_councillors_2022.csv",
        "local_election_end": "opencouncildata_councillors_2026.csv",
    },
}


def main():
    which = sys.argv[1:] or ["1", "2"]
    for pair in which:
        result = pipeline.run(PAIRS[pair])
        print(f"pair {pair}: {result}")


if __name__ == "__main__":
    main()
