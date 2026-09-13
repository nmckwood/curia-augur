"""Tests for the four lambda handlers in apps/.

The handlers live outside any package, so each is loaded from its file path. The three
container-image handlers are thin wrappers and are tested by stubbing the core module
they delegate to. The files_api handler imports boto3 at module scope, so a stub boto3 is
injected into sys.modules before import — no moto, no credentials, no network.
"""

import importlib.util
import json
import sys
import types

import pytest

from tests.conftest import REPO_ROOT


def _load(name, relpath):
    """Import a handler module from its path under apps/."""
    spec = importlib.util.spec_from_file_location(name, f"{REPO_ROOT}/{relpath}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


# --- data ingestion handler --------------------------------------------------


def test_data_ingestion_handler_delegates_to_the_ingestion_pipeline(monkeypatch):
    module = _load("handler_data_ingestion", "apps/data_ingestion/app.py")
    seen = {}

    def fake_run(event):
        seen["event"] = event
        return {"ok": 1}

    monkeypatch.setattr(module.pipeline, "run", fake_run)

    event = {"deprivation_file_start": "a.json"}
    assert module.lambda_handler(event, None) == {"ok": 1}
    assert seen["event"] is event


# --- ML pipeline handler -----------------------------------------------------


def test_ml_pipeline_handler_delegates_to_the_ml_pipeline(monkeypatch):
    module = _load("handler_ml_pipeline", "apps/ml_pipeline/app.py")
    monkeypatch.setattr(module.pipeline, "run", lambda event: {"analysis_key": "k"})

    result = module.lambda_handler({"output_key": "output/x.json"}, None)

    assert result == {"analysis_key": "k"}


# --- prediction handler (loop guard) -----------------------------------------


@pytest.fixture
def prediction_handler():
    return _load("handler_prediction", "apps/prediction/app.py")


def _analysis(predicted):
    """An analysis that either has, or is missing, the prediction outputs."""
    constituency = {"Local Authority District name": "A"}
    if predicted:
        constituency["change_factor_deprivation_key_indices"] = 0
    return {
        "meta": {"key_indices": ["Income Rank"] if predicted else []},
        "constituencies": [constituency],
    }


def test_needs_prediction_is_true_without_key_indices(prediction_handler):
    assert prediction_handler._needs_prediction(_analysis(predicted=False)) is True


def test_needs_prediction_is_true_when_a_constituency_lacks_the_field(
    prediction_handler,
):
    analysis = _analysis(predicted=True)
    analysis["constituencies"].append({"Local Authority District name": "B"})
    assert prediction_handler._needs_prediction(analysis) is True


def test_needs_prediction_is_false_once_everything_is_populated(prediction_handler):
    assert prediction_handler._needs_prediction(_analysis(predicted=True)) is False


def test_needs_prediction_on_an_empty_analysis_is_true(prediction_handler):
    assert prediction_handler._needs_prediction({}) is True


def test_prediction_handler_skips_with_fewer_than_two_analyses(
    prediction_handler, monkeypatch
):
    monkeypatch.setattr(
        prediction_handler.io, "list_output_keys", lambda prefix: ["analysis/a.json"]
    )

    result = prediction_handler.lambda_handler({}, None)

    assert result == {"skipped": "fewer than 2 analyses present", "count": 1}


def test_prediction_handler_ignores_non_json_keys(prediction_handler, monkeypatch):
    monkeypatch.setattr(
        prediction_handler.io,
        "list_output_keys",
        lambda prefix: ["analysis/a.json", "analysis/notes.txt"],
    )

    assert prediction_handler.lambda_handler({}, None)["count"] == 1


def test_prediction_handler_breaks_the_s3_event_loop_once_all_are_predicted(
    prediction_handler, monkeypatch
):
    """Writing the augmented analyses re-fires this lambda; without the guard it would
    cascade forever."""
    monkeypatch.setattr(
        prediction_handler.io,
        "list_output_keys",
        lambda prefix: ["analysis/a.json", "analysis/b.json"],
    )
    monkeypatch.setattr(
        prediction_handler.io,
        "read_output_text",
        lambda key: json.dumps(_analysis(predicted=True)),
    )
    called = []
    monkeypatch.setattr(
        prediction_handler.predict, "run", lambda items: called.append(items)
    )

    result = prediction_handler.lambda_handler({}, None)

    assert result == {"skipped": "all analyses already predicted"}
    assert called == []


def test_prediction_handler_runs_when_an_analysis_still_needs_prediction(
    prediction_handler, monkeypatch
):
    monkeypatch.setattr(
        prediction_handler.io,
        "list_output_keys",
        lambda prefix: ["analysis/a.json", "analysis/b.json"],
    )
    monkeypatch.setattr(
        prediction_handler.io,
        "read_output_text",
        lambda key: json.dumps(_analysis(predicted=key.endswith("a.json"))),
    )
    seen = {}

    def fake_run(items):
        seen["items"] = items
        return {"key_indices": ["x"]}

    monkeypatch.setattr(prediction_handler.predict, "run", fake_run)

    result = prediction_handler.lambda_handler({}, None)

    assert result == {"key_indices": ["x"]}
    assert seen["items"] == [
        {"analysis_key": "analysis/a.json"},
        {"analysis_key": "analysis/b.json"},
    ]


# --- files API handler -------------------------------------------------------


class _FakeS3Client:
    def __init__(self, keys=(), raise_on_list=None):
        self.keys = list(keys)
        self.raise_on_list = raise_on_list

    def get_paginator(self, _operation):
        client = self

        class _Paginator:
            def paginate(self_inner, Bucket, Prefix):  # noqa: N803
                if client.raise_on_list:
                    raise client.raise_on_list
                yield {"Contents": [{"Key": k} for k in client.keys]}

        return _Paginator()

    def generate_presigned_url(self, _op, Params, ExpiresIn):  # noqa: N803
        return f"https://signed/{Params['Key']}?ttl={ExpiresIn}"


@pytest.fixture
def files_api(monkeypatch):
    """Load apps/files_api/app.py with a stub boto3 in place.

    Returns a factory: ``files_api(keys=..., raise_on_list=...)`` -> module.
    """

    def _make(keys=("analysis/a.json",), raise_on_list=None, ttl="3600"):
        client = _FakeS3Client(keys, raise_on_list)
        fake_boto3 = types.ModuleType("boto3")
        fake_boto3.client = lambda service: client
        monkeypatch.setitem(sys.modules, "boto3", fake_boto3)
        monkeypatch.setenv("OUTPUT_BUCKET", "test-output-bucket")
        monkeypatch.setenv("URL_TTL_SECONDS", ttl)
        return _load("handler_files_api", "apps/files_api/app.py")

    return _make


def _authed_event():
    return {"requestContext": {"authorizer": {"claims": {"sub": "user-1"}}}}


def test_files_api_rejects_an_unauthenticated_request(files_api):
    module = files_api()

    response = module.lambda_handler({}, None)

    assert response["statusCode"] == 401
    assert json.loads(response["body"]) == {"message": "unauthorized"}


def test_files_api_rejects_an_empty_authorizer(files_api):
    module = files_api()
    event = {"requestContext": {"authorizer": {}}}
    assert module.lambda_handler(event, None)["statusCode"] == 401


def test_files_api_accepts_rest_api_authorizer_claims(files_api):
    module = files_api()
    assert module._is_authenticated(_authed_event()) is True


def test_files_api_accepts_http_api_jwt_claims(files_api):
    """HTTP APIs nest the claims under 'jwt' rather than exposing them directly."""
    module = files_api()
    event = {"requestContext": {"authorizer": {"jwt": {"claims": {"sub": "u"}}}}}
    assert module._is_authenticated(event) is True


def test_files_api_returns_presigned_urls_for_each_analysis(files_api):
    module = files_api(keys=("analysis/a.json", "analysis/b.json"))

    response = module.lambda_handler(_authed_event(), None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert [item["filename"] for item in body] == ["a.json", "b.json"]
    assert body[0]["pre_signed_url"] == "https://signed/analysis/a.json?ttl=3600"


def test_files_api_honours_a_custom_url_ttl(files_api):
    module = files_api(ttl="60")
    body = json.loads(module.lambda_handler(_authed_event(), None)["body"])
    assert body[0]["pre_signed_url"].endswith("ttl=60")


def test_files_api_skips_non_json_objects(files_api):
    module = files_api(keys=("analysis/a.json", "analysis/README.md"))
    body = json.loads(module.lambda_handler(_authed_event(), None)["body"])
    assert [item["filename"] for item in body] == ["a.json"]


def test_files_api_returns_404_when_there_is_nothing_to_serve(files_api):
    module = files_api(keys=())

    response = module.lambda_handler(_authed_event(), None)

    assert response["statusCode"] == 404
    assert json.loads(response["body"])["message"] == "no analysis outputs available"


def test_files_api_returns_500_on_an_s3_failure(files_api):
    module = files_api(raise_on_list=RuntimeError("bucket on fire"))

    response = module.lambda_handler(_authed_event(), None)

    assert response["statusCode"] == 500
    body = json.loads(response["body"])
    assert body["message"] == "internal error"
    assert "bucket on fire" in body["detail"]


def test_files_api_always_sets_cors_headers(files_api):
    module = files_api()
    for event in ({}, _authed_event()):
        headers = module.lambda_handler(event, None)["headers"]
        assert headers["Access-Control-Allow-Origin"] == "*"
        assert headers["Content-Type"] == "application/json"
