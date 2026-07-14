"""Data ingestion pipeline orchestration.

Reads the four input files named in the event, aggregates and joins them, writes
``output/deprivation-election-data-<key>.json`` plus the unused ``.log`` (REQ Data-Ingestion).
This module is the single entry point imported by both the lambda handler and the local
runner; it performs no AWS-specific work itself (that lives in common/io).
"""

import json
import re

from curia_core.common import io
from curia_core.common.schemas import (
    DECILE_DELTA_KEYS,
    ingestion_output_schema,
)
from curia_core.ingestion import deprivation, election, joining
from curia_core.ingestion.readers import read_records


def _year(filename):
    match = re.search(r"(19|20)\d{2}", filename)
    return match.group(0) if match else "unknown"


def _composite_key(event):
    return (
        f"d_{_year(event['deprivation_file_start'])}"
        f"_d_{_year(event['deprivation_file_end'])}"
        f"_le_{_year(event['local_election_start'])}"
        f"_le_{_year(event['local_election_end'])}"
    )


def run(event):
    """Run the ingestion pipeline for one comparison pair.

    ``event`` matches REQ Data-Ingestion-3. Returns a dict of output locations/counts.
    """
    key = _composite_key(event)
    log_lines = []

    dep_start = deprivation.aggregate_to_lad(
        read_records(io.resolve_input_path(event["deprivation_file_start"]))
    )
    dep_end = deprivation.aggregate_to_lad(
        read_records(io.resolve_input_path(event["deprivation_file_end"]))
    )
    dep_deltas = deprivation.compute_deltas(dep_start, dep_end)

    for lad in set(dep_start) | set(dep_end):
        if lad not in dep_deltas:
            log_lines.append(
                f"could not compute deprivation delta for '{lad}' between "
                f"{event['deprivation_file_start']} and {event['deprivation_file_end']} "
                f"(missing in one year or incomplete fields)"
            )

    election_results = election.build_election_results(
        read_records(io.resolve_input_path(event["local_election_start"])),
        read_records(io.resolve_input_path(event["local_election_end"])),
    )

    matches, unmatched = joining.match_councils_to_lads(
        list(election_results.keys()), list(dep_deltas.keys())
    )
    for council, best_lad, score in unmatched:
        log_lines.append(
            f"could not join council '{council}' with any Local Authority District name "
            f"between {event['local_election_start']} and {event['local_election_end']} "
            f"as the fuzzy match did not find anything (best='{best_lad}', score={score})"
        )

    schema = ingestion_output_schema()
    output = []
    used_lads = set()
    for council, lad in matches.items():
        used_lads.add(lad)
        entry = {
            "Local Authority District name": lad,
            "deprivation": dep_deltas[lad],
            "local_election_results": election_results[council],
        }
        errors = io.validation_errors([entry], schema)
        if errors:
            log_lines.append(
                f"dropped entry for '{lad}'/'{council}' due to validation errors: "
                + "; ".join(errors)
            )
            continue
        output.append(entry)

    for lad in dep_deltas:
        if lad not in used_lads:
            log_lines.append(
                f"deprivation LAD '{lad}' had no matching election council and was unused"
            )

    json_key = f"output/deprivation-election-data-{key}.json"
    log_key = f"output/unused-deprivation-election-data-{key}.log"
    json_loc = io.write_output_json(json_key, output)
    log_loc = io.write_output_text(log_key, "\n".join(log_lines) + "\n")

    return {
        "composite_key": key,
        "output_json": json_loc,
        "output_log": log_loc,
        "n_entries": len(output),
        "n_unused": len(log_lines),
        "output_key": json_key,
    }


def lambda_event_from_s3(event):
    """Placeholder for symmetry; ingestion is invoked directly, not via S3 event."""
    return event


# Re-exported for the ML pipeline / tests that need the feature list.
FEATURE_KEYS = DECILE_DELTA_KEYS


if __name__ == "__main__":
    import sys

    print(json.dumps(run(json.loads(sys.argv[1])), indent=2))
