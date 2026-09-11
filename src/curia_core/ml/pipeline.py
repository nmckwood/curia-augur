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

    # get the existing composite key created by the data ingestion pipeline
    output_key = _output_key_from_event(event)

    # create a new key for the ml data using a prefix and the composite key from previous step
    composite_key = _composite_key(output_key)

    entries = json.loads(io.read_output_text(output_key))

    # for each LAD for each deprivation delta and decile delta key/value
    # in the order of the machine learning feature keys (the indices we care 
    # about) transform into a feature vector EG Hammersmith&Fulham [15.1, 10.2 ...]
    # where the values are the transformed data
    matrix, rows = features.build_feature_matrix(entries)

    # We must normalise the features and clean the data so the ML model output is not skewed
    # for each column (I.E deoprivation indices) in the matrix find features without meanginful
    # variation. Each value is normalised so find the standard deviationsa from mean typically
    # resulting in values between +3 and -3 (but not constrained to this)
    # z = ( x - μ ) / σ (https://www.investopedia.com/terms/z/zscore.asp)
    ## z = z-score
    ## x = the value being evaluated
    ## μ = the mean
    ## σ = the standard deviation
    # the z-score allows us to ignore values where 95% of the z value are the same meaning the 
    # deprivation indices is constant and hence does not offer value for analysis
    normalized = features.zscore_normalize(matrix)

    # log the not used deprivation indixes
    degenerate_features = [
        key
        for key, is_degenerate in zip(
            ML_FEATURE_KEYS, features.degenerate_feature_mask(matrix)
        )
        if is_degenerate
    ]

    # key area where the ML K-means model is run
    ## https://scikit-learn.org/stable/modules/generated/sklearn.cluster.KMeans.html
    # Here we essentially use our unsupervised algorthim k-means to group LAD's based
    # on the normalized deprivation data with a dynamically chosen value for k.
    # labels: which cluster each of our LADs has been placed in
    # _: the centroid -- not used
    # best_k: the optimal value of k for cluster cohesiveness and seperation
    # method: how we found k, we use silhoutee
    labels, _, best_k, method = cluster.select_k_and_fit(normalized)

    # do data preperation for the following analysis
    change_factors = [r["change_factor"] for r in rows]

    # dictionary summary of each of the matrix rows, converting matrix to JSON
    summaries = stats.cluster_summaries(labels, change_factors, normalized)

    # mark the cluster which has the highest change likelyhood
    high_change_id = stats.mark_high_change_cluster(summaries)

    # for each deprication indices use its standard deviation in the high change cluster
    # to compare it against its mean value in other clusters then rank the features, returning
    # a ranked list of most important deprivation indices
    importance = stats.feature_importance(labels, normalized, high_change_id)

    # score the cluster based on if its prediciton is 1 and its change_factor is 1
    cluster_preds, cluster_accuracy = stats.score_clusters(
        summaries, labels, change_factors, high_change_id
    )

    # convert the vectors into 2d so they can be easily visualised
    # essentially finding the mean path of all the data points
    coords = features.pca_2d(normalized)

    # prepare the ML data for output to the next stage
    constituencies = []
    for row, label, coord, cluster_pred in zip(rows, labels, coords, cluster_preds):
        constituencies.append(
            {
                "Local Authority District name": row["Local Authority District name"],
                "council": row["council"],
                "cluster_id": int(label),
                "change_factor": row["change_factor"],
                "change_factor_cluster": int(cluster_pred),
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
            "cluster_accuracy": cluster_accuracy,
            "degenerate_features": degenerate_features,
        },
        "clusters": summaries,
        # "significance_test": significance,
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
        # "significant": significance["significant"],
        "n_constituencies": len(entries),
    }
