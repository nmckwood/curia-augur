"""Machine learning pipeline orchestration (REQ Machine-Learning-Pipeline).

Triggered by an S3 ObjectCreated event on the ingestion output (prefix ``output/``), or
invoked directly with ``{"output_key": "output/deprivation-election-data-<key>.json"}``.
Reads the ingestion JSON, clusters LADs by deprivation decile deltas, tests significance,
ranks characterizing features, and writes the analysis JSON to prefix ``analysis/``.
"""

import json
import os
import re
from datetime import datetime, timezone

from curia_core.common import io
from curia_core.common.schemas import ML_FEATURE_KEYS, ml_output_schema
from curia_core.ml import cluster, features, stats


def _output_key_from_event(event):
    if "output_key" in event:
        return event["output_key"]
    records = event.get("Records") or []
    if records:
        return records[0]["s3"]["object"]["key"]
    raise ValueError("event has neither 'output_key' nor S3 Records")


def _composite_key(output_key):
    name = os.path.basename(output_key)
    match = re.search(r"deprivation-election-data-(.+)\.json$", name)
    return match.group(1) if match else name


def run(event):
    """Run the ML pipeline for one ingestion output file. Returns output location/meta."""
    output_key = _output_key_from_event(event)
    composite_key = _composite_key(output_key)

    entries = json.loads(io.read_output_text(output_key))
    matrix, rows = features.build_feature_matrix(entries)
    normalized = features.zscore_normalize(matrix)

    labels, _centroids, best_k, method = cluster.select_k_and_fit(normalized)

    change_factors = [r["change_factor"] for r in rows]
    summaries = stats.cluster_summaries(labels, change_factors, normalized)
    high_change_id = stats.mark_high_change_cluster(summaries)
    significance = stats.significance_test(labels, change_factors)
    importance = stats.feature_importance(labels, normalized, high_change_id)

    coords = features.pca_2d(normalized)
    constituencies = []
    for row, label, coord in zip(rows, labels, coords):
        constituencies.append(
            {
                "Local Authority District name": row["Local Authority District name"],
                "council": row["council"],
                "cluster_id": int(label),
                "change_factor": row["change_factor"],
                "deprivation_deciles": row["deprivation_deciles"],
                "pca_x": float(coord[0]),
                "pca_y": float(coord[1]),
            }
        )

    analysis = {
        "meta": {
            "k": int(best_k),
            "k_selection_method": method,
            "features_used": list(ML_FEATURE_KEYS),
            "normalization": "z-score",
            "n_constituencies": len(entries),
            "generated_at": datetime.now(timezone.utc).isoformat(),
        },
        "clusters": summaries,
        "significance_test": significance,
        "feature_importance": importance,
        "constituencies": constituencies,
    }

    errors = io.validation_errors(analysis, ml_output_schema())
    if errors:
        raise ValueError("ML output failed schema validation: " + "; ".join(errors))

    analysis_key = f"analysis/analysis-{composite_key}.json"
    location = io.write_output_json(analysis_key, analysis)
    return {
        "analysis_key": analysis_key,
        "location": location,
        "k": int(best_k),
        "significant": significance["significant"],
        "n_constituencies": len(entries),
    }
