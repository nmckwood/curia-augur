"""Tests for curia_core.common.schemas — the field-name constants and JSON schemas
every other stage is validated against."""

import pytest
from jsonschema import Draft202012Validator

from curia_core.common import schemas
from curia_core.common.io import validation_errors
from tests.conftest import ingestion_entry


def test_domain_field_helpers_compose_the_documented_names():
    assert schemas.rank_field("Income") == "Income Rank (where 1 is most deprived)"
    assert schemas.decile_field("Crime") == (
        "Crime Decile (where 1 is most deprived 10% of LSOAs)"
    )


def test_there_are_eight_domains_and_sixteen_input_fields():
    assert len(schemas.DOMAINS) == 8
    assert len(schemas.DEPRIVATION_INPUT_FIELDS) == 16
    assert len(schemas.DEPRIVATION_DELTA_KEYS) == 16
    assert len(schemas.DECILE_DELTA_KEYS) == 8
    assert len(schemas.RANK_DELTA_KEYS) == 8
    # Rank and decile keys partition the delta keys with no overlap.
    assert set(schemas.RANK_DELTA_KEYS) | set(schemas.DECILE_DELTA_KEYS) == set(
        schemas.DEPRIVATION_DELTA_KEYS
    )
    assert not set(schemas.RANK_DELTA_KEYS) & set(schemas.DECILE_DELTA_KEYS)


def test_ml_feature_keys_are_all_sixteen_deltas():
    assert schemas.ML_FEATURE_KEYS == list(schemas.DEPRIVATION_DELTA_KEYS)


@pytest.mark.parametrize(
    "schema_factory",
    [schemas.ingestion_output_schema, schemas.ml_output_schema],
)
def test_schemas_are_themselves_valid_json_schema(schema_factory):
    Draft202012Validator.check_schema(schema_factory())


def test_ingestion_schema_accepts_a_well_formed_entry():
    entry = ingestion_entry("Testshire", change_factor=1)
    assert validation_errors([entry], schemas.ingestion_output_schema()) == []


def test_ingestion_schema_allows_float_rank_deltas_but_not_float_decile_deltas():
    """Rank deltas are percentile points (float); decile deltas are whole deciles."""
    entry = ingestion_entry("Testshire", change_factor=0)
    schema = schemas.ingestion_output_schema()

    entry["deprivation"][schemas.RANK_DELTA_KEYS[0]] = 1.2345
    assert validation_errors([entry], schema) == []

    entry["deprivation"][schemas.DECILE_DELTA_KEYS[0]] = 1.5
    errors = validation_errors([entry], schema)
    assert errors and "1.5 is not of type 'integer'" in errors[0]


def test_ingestion_schema_rejects_a_missing_required_block():
    entry = ingestion_entry("Testshire", change_factor=0)
    del entry["deprivation"]
    errors = validation_errors([entry], schemas.ingestion_output_schema())
    assert any("deprivation" in e for e in errors)


def test_ingestion_schema_rejects_unknown_top_level_properties():
    entry = ingestion_entry("Testshire", change_factor=0)
    entry["surprise"] = 1
    assert validation_errors([entry], schemas.ingestion_output_schema())


def test_ml_schema_accepts_the_requirements_4_cluster_accuracy_fields():
    analysis = {
        "meta": {
            "k": 2,
            "features_used": list(schemas.ML_FEATURE_KEYS),
            "n_constituencies": 1,
            "cluster_accuracy": {"accuracy": 0.5, "n_correct": 1, "n_total": 2},
        },
        "clusters": [
            {
                "cluster_id": 0,
                "size": 1,
                "mean_change_factor": 0.0,
                "is_high_change_cluster": False,
                "predicted_change_factor": 0,
                "n_correct": 1,
                "accuracy": 1.0,
                "accuracy_rank": 1,
                "centroid": {"x": 0.0},
            }
        ],
        "feature_importance": [
            {"feature": "f", "deviation_score": 0.0, "rank": 1},
        ],
        "constituencies": [
            {
                "Local Authority District name": "Testshire",
                "cluster_id": 0,
                "change_factor": 0,
                "change_factor_cluster": 0,
            }
        ],
    }
    assert validation_errors(analysis, schemas.ml_output_schema()) == []


def test_ml_schema_accepts_the_prediction_baseline_block():
    analysis = {
        "meta": {
            "k": 2,
            "features_used": [],
            "n_constituencies": 0,
            "prediction": {
                "holdout_accuracy": 0.5,
                "test_size": 10,
                "baseline_accuracy": 0.5,
                "baseline": {
                    "majority_class": 0,
                    "holdout_accuracy": 0.5,
                    "all_accuracy": 0.5,
                    "n_correct_all": 5,
                    "n_total_all": 10,
                },
            },
        },
        "clusters": [],
        "feature_importance": [],
        "constituencies": [],
    }
    assert validation_errors(analysis, schemas.ml_output_schema()) == []


def test_ml_schema_rejects_an_unknown_k_selection_method():
    analysis = {
        "meta": {
            "k": 2,
            "k_selection_method": "coin-toss",
            "features_used": [],
            "n_constituencies": 0,
        },
        "clusters": [],
        "feature_importance": [],
        "constituencies": [],
    }
    assert validation_errors(analysis, schemas.ml_output_schema())
