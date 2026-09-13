"""Read input records from .xlsx / .json / .csv (REQ Data-Ingestion-9).

Pure functions returning lists of plain dicts, so the same code runs locally and in AWS.
"""

import csv
import json
import os
import pandas as pd

from curia_core.common.schemas import LAD_NAME_PREFIX


def read_records(path):
    """Return the file contents as a list of dict records, dispatched on extension."""
    ext = os.path.splitext(path)[1].lower()
    if ext == ".json":
        return _read_json(path)
    if ext == ".csv":
        return _read_csv(path)
    if ext in (".xlsx", ".xls"):
        return _read_xlsx(path)
    raise ValueError(f"unsupported file type: {ext}")


def _read_json(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if isinstance(data, dict):
        # Allow {"records": [...]} or a single object.
        return data.get("records", [data])
    return data


def _read_csv(path):
    with open(path, newline="", encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))


def _read_xlsx(path):

    frame = pd.read_excel(path)
    return json.loads(frame.to_json(orient="records"))


def detect_lad_column(record):
    """Find the Local-Authority-District-name column, ignoring the "(year)" suffix.

    Returns the matching key, or None if absent.
    """
    for key in record:
        if key.startswith(LAD_NAME_PREFIX):
            return key
    return None
