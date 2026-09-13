"""
Local-vs-S3 IO abstraction plus schema validation.

Behaviour is switched by the ``CURIA_LOCAL`` environment flag (REQ: "there must be an
env flag which is true for when running locally which reads files locally rather than
from s3"). All functions are pure-ish helpers; boto3 is imported lazily so local runs
need no AWS credentials or the boto3 package.
"""

import json
import os

from jsonschema import Draft202012Validator

# Repo root is three levels up from this file: src/curia_core/common/io.py -> repo root.
_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def is_local():
    return os.environ.get("CURIA_LOCAL", "").strip().lower() in ("1", "true", "yes")


def _local_data_dir():
    return os.environ.get("CURIA_LOCAL_DATA_DIR", os.path.join(_REPO_ROOT, "data"))


def _local_output_dir():
    path = os.environ.get(
        "CURIA_LOCAL_OUTPUT_DIR", os.path.join(_REPO_ROOT, "local_output")
    )
    os.makedirs(path, exist_ok=True)
    return path


def _input_bucket():
    return os.environ["INPUT_BUCKET"]


def _output_bucket():
    return os.environ["OUTPUT_BUCKET"]


def _s3():
    import boto3  # lazy: only needed in AWS mode

    return boto3.client("s3")


def resolve_input_path(filename):
    """
    Return a local filesystem path for an input data file.

    Local mode: search recursively under the data dir for the given filename.
    AWS mode: download s3://INPUT_BUCKET/<filename> to /tmp and return that path.
    """
    if is_local():
        for root, _dirs, files in os.walk(_local_data_dir()):
            if filename in files:
                return os.path.join(root, filename)
        raise FileNotFoundError(
            f"{filename} not found under {_local_data_dir()}"
        )
    dest = os.path.join("/tmp", os.path.basename(filename))
    _s3().download_file(_input_bucket(), filename, dest)
    return dest


def write_output_text(key, text):
    """
    Write text output to the output location under prefix ``output/``.

    Local mode: writes to the local output dir. AWS mode: puts to OUTPUT_BUCKET.
    ``key`` should already include any prefix (e.g. ``output/foo.json``).
    """
    if is_local():
        dest = os.path.join(_local_output_dir(), key)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "w", encoding="utf-8") as fh:
            fh.write(text)
        return dest
    _s3().put_object(Bucket=_output_bucket(), Key=key, Body=text.encode("utf-8"))
    return f"s3://{_output_bucket()}/{key}"


def list_output_keys(prefix):
    """
    List output object keys under ``prefix`` (e.g. 'analysis/').

    Local mode: walk the local output dir and return keys relative to it. AWS mode:
    paginate ``list_objects_v2`` on OUTPUT_BUCKET.
    """
    if is_local():
        base = _local_output_dir()
        root = os.path.join(base, prefix)
        keys = []
        for dirpath, _dirs, files in os.walk(root):
            for name in files:
                full = os.path.join(dirpath, name)
                keys.append(os.path.relpath(full, base).replace(os.sep, "/"))
        return sorted(keys)
    paginator = _s3().get_paginator("list_objects_v2")
    keys = []
    for page in paginator.paginate(Bucket=_output_bucket(), Prefix=prefix):
        for obj in page.get("Contents", []):
            keys.append(obj["Key"])
    return sorted(keys)


def read_output_text(key):
    """Read back a previously written output object (used by the ML pipeline)."""
    if is_local():
        with open(os.path.join(_local_output_dir(), key), encoding="utf-8") as fh:
            return fh.read()
    obj = _s3().get_object(Bucket=_output_bucket(), Key=key)
    return obj["Body"].read().decode("utf-8")


def write_output_json(key, obj):
    return write_output_text(key, json.dumps(obj, indent=2))


def validation_errors(instance, schema):
    """
    Return a list of human-readable validation error strings (never raises).

    Callers log these rather than aborting, per REQ (invalid entries are logged).
    """

    validator = Draft202012Validator(schema)
    errors = []
    for err in sorted(validator.iter_errors(instance), key=lambda e: list(e.path)):
        loc = "/".join(str(p) for p in err.path) or "<root>"
        errors.append(f"{loc}: {err.message}")
    return errors
