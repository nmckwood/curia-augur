"""Field-name constants and JSON schemas derived from docs/REQUIREMENTS.md.

Everything here is data (module-level constants / pure functions) so it can be imported
by both the lambda handlers and the local /tools runners without side effects.
"""

# --- Deprivation field naming -------------------------------------------------
# The eight IoD domains, in the fixed order used throughout the output schema.
DOMAINS = [
    "Index of Multiple Deprivation (IMD)",
    "Income",
    "Employment",
    "Education, Skills and Training",
    "Health Deprivation and Disability",
    "Crime",
    "Barriers to Housing and Services",
    "Living Environment",
]

RANK_SUFFIX = " Rank (where 1 is most deprived)"
DECILE_SUFFIX = " Decile (where 1 is most deprived 10% of LSOAs)"
DELTA_SUFFIX = " delta"

# Prefix used to detect the Local-Authority-District-name column regardless of the
# varying "(2013)" / "(2019)" / "(2024)" year suffix present across input files.
LAD_NAME_PREFIX = "Local Authority District name"


def rank_field(domain):
    return domain + RANK_SUFFIX


def decile_field(domain):
    return domain + DECILE_SUFFIX


# The 16 raw deprivation fields (rank + decile per domain) present in the input data.
DEPRIVATION_INPUT_FIELDS = []
for _domain in DOMAINS:
    DEPRIVATION_INPUT_FIELDS.append(rank_field(_domain))
    DEPRIVATION_INPUT_FIELDS.append(decile_field(_domain))

# The 16 "... delta" keys emitted in the ingestion output (rank + decile per domain).
DEPRIVATION_DELTA_KEYS = [f + DELTA_SUFFIX for f in DEPRIVATION_INPUT_FIELDS]

# The 8 decile-delta keys (kept for the per-constituency display block).
DECILE_DELTA_KEYS = [decile_field(d) + DELTA_SUFFIX for d in DOMAINS]

# The 8 rank-delta keys. These are real-valued: IoD re-bases its ranks every edition
# (32,844 LSOAs in 2015/2019 vs 33,755 in 2025), so ingestion converts ranks to
# within-edition national percentiles before differencing. A rank delta is therefore a
# change in percentile POINTS (-100..100), not a change in raw rank position.
RANK_DELTA_KEYS = [rank_field(d) + DELTA_SUFFIX for d in DOMAINS]

# KMeans feature set. REQ ML-4 said "decile delta only", but at LAD-mean level the
# decile deltas round to mostly 0 and carry almost no signal, so clustering collapsed to
# full 16 rank+decile deltas instead: the rank deltas are continuous (0..~30k) and carry
# the real signal, while z-score normalization puts every feature on a comparable scale.
ML_FEATURE_KEYS = list(DEPRIVATION_DELTA_KEYS)


# --- Ingestion output schema (REQUIREMENTS §Data-Ingestion-5) -----------------
def ingestion_output_schema():
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "Local Authority Deprivation and Election Results",
        "type": "array",
        "items": {
            "type": "object",
            "properties": {
                "Local Authority District name": {"type": "string"},
                "deprivation": {
                    "type": "object",
                    # Rank deltas are percentile points (float); decile deltas are whole
                    # deciles (int). See RANK_DELTA_KEYS.
                    "properties": {
                        k: {"type": "number" if k in RANK_DELTA_KEYS else "integer"}
                        for k in DEPRIVATION_DELTA_KEYS
                    },
                    "required": list(DEPRIVATION_DELTA_KEYS),
                    "additionalProperties": False,
                },
                "local_election_results": {
                    "type": "object",
                    "properties": {
                        "council": {"type": "string"},
                        "change_factor": {"type": "integer"},
                    },
                    "required": ["council", "change_factor"],
                    "additionalProperties": {"type": "integer"},
                },
            },
            "required": [
                "Local Authority District name",
                "deprivation",
                "local_election_results",
            ],
            "additionalProperties": False,
        },
    }


# --- ML output schema (REQUIREMENTS §Machine-Learning-Pipeline-6) -------------
def ml_output_schema():
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "Deprivation-Election KMeans Analysis Output",
        "type": "object",
        "properties": {
            "meta": {
                "type": "object",
                "properties": {
                    "k": {"type": "integer"},
                    "k_selection_method": {
                        "type": "string",
                        "enum": ["elbow", "silhouette", "manual"],
                    },
                    "features_used": {"type": "array", "items": {"type": "string"}},
                    "normalization": {
                        "type": "string",
                        "enum": ["z-score", "min-max", "none"],
                    },
                    "n_constituencies": {"type": "integer"},
                    "generated_at": {"type": "string", "format": "date-time"},
                    "degenerate_features": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Features zeroed by the near-constant guard in features.zscore_normalize; they carry no spread and were excluded from the distance metric, so a 0 importance score for these means 'not usable', not 'not important'",
                    },
                    "cluster_accuracy": {
                        "type": "object",
                        "description": "Accuracy of change_factor_cluster over all councils (REQUIREMENTS_4)",
                        "properties": {
                            "accuracy": {"type": "number"},
                            "n_correct": {"type": "integer"},
                            "n_total": {"type": "integer"},
                        },
                        "required": ["accuracy", "n_correct", "n_total"],
                        "additionalProperties": False,
                    },
                    "key_indices": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Deprivation indices common to both analyses' high-change clusters (REQUIREMENTS_3)",
                    },
                    "prediction": {
                        "type": "object",
                        "description": "Held-out prediction metrics from the key-indices model (REQUIREMENTS_3)",
                        "properties": {
                            "method": {"type": "string"},
                            "holdout_accuracy": {"type": "number"},
                            "train_accuracy": {"type": "number"},
                            "train_size": {"type": "integer"},
                            "test_size": {"type": "integer"},
                            "baseline_accuracy": {"type": "number"},
                            "baseline": {
                                "type": "object",
                                "description": "The 'no ML' bar: always predict the most common change_factor (REQUIREMENTS_4 UI)",
                                "properties": {
                                    "majority_class": {"type": "integer"},
                                    "holdout_accuracy": {"type": "number"},
                                    "all_accuracy": {"type": "number"},
                                    "n_correct_all": {"type": "integer"},
                                    "n_total_all": {"type": "integer"},
                                },
                                "required": [
                                    "majority_class",
                                    "holdout_accuracy",
                                    "all_accuracy",
                                ],
                                "additionalProperties": False,
                            },
                            "per_year_holdout_accuracy": {"type": "number"},
                            "per_year_train_accuracy": {"type": "number"},
                            "per_year_indices": {
                                "type": "array",
                                "items": {"type": "string"},
                            },
                            "per_year_index_details": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "feature": {"type": "string"},
                                        "holdout_accuracy": {"type": "number"},
                                        "rank": {"type": "integer"},
                                    },
                                    "required": ["feature", "holdout_accuracy", "rank"],
                                    "additionalProperties": False,
                                },
                            },
                        },
                        "required": ["holdout_accuracy", "test_size"],
                        "additionalProperties": False,
                    },
                },
                "required": ["k", "features_used", "n_constituencies"],
                "additionalProperties": False,
            },
            "clusters": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "cluster_id": {"type": "integer"},
                        "size": {"type": "integer"},
                        "mean_change_factor": {"type": "number"},
                        "median_change_factor": {"type": "number"},
                        "is_high_change_cluster": {"type": "boolean"},
                        "predicted_change_factor": {"type": "integer"},
                        "n_correct": {"type": "integer"},
                        "accuracy": {"type": "number"},
                        "accuracy_rank": {"type": "integer"},
                        "centroid": {
                            "type": "object",
                            "additionalProperties": {"type": "number"},
                        },
                    },
                    "required": ["cluster_id", "size", "mean_change_factor", "centroid"],
                    "additionalProperties": False,
                },
            },
            "feature_importance": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "feature": {"type": "string"},
                        "high_change_cluster_mean": {"type": "number"},
                        "other_clusters_mean": {"type": "number"},
                        "deviation_score": {"type": "number"},
                        "rank": {"type": "integer"},
                    },
                    "required": ["feature", "deviation_score", "rank"],
                    "additionalProperties": False,
                },
            },
            "constituencies": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "Local Authority District name": {"type": "string"},
                        "council": {"type": "string"},
                        "cluster_id": {"type": "integer"},
                        "change_factor": {"type": "integer"},
                        "change_factor_cluster": {"type": "integer"},
                        "deprivation_deciles": {
                            "type": "object",
                            "additionalProperties": {"type": "integer"},
                        },
                        "pca_x": {"type": "number"},
                        "pca_y": {"type": "number"},
                        "change_factor_deprivation_key_indices": {"type": "integer"},
                        "change_factor_per_year_key_indices": {"type": "integer"},
                    },
                    "required": [
                        "Local Authority District name",
                        "cluster_id",
                        "change_factor",
                    ],
                    "additionalProperties": False,
                },
            },
        },
        "required": ["meta", "clusters", "feature_importance", "constituencies"],
        "additionalProperties": False,
    }
