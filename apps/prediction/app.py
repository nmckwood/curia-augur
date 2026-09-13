"""Cross-analysis prediction lambda (container image), triggered by S3 ObjectCreated on
the analysis/ prefix. Thin wrapper over curia_core.ml.predict.

Loop guard: writing the augmented analyses re-fires this event, so we no-op (write
nothing) unless there are >= 2 analyses AND at least one is missing the prediction
output. Once every analysis carries meta.key_indices and the per-constituency field, the
next invocation exits without writing and the cascade stops.
"""

import json

from curia_core.common import io
from curia_core.ml import predict


def _needs_prediction(analysis):
    if not analysis.get("meta", {}).get("key_indices"):
        return True
    return any(
        "change_factor_deprivation_key_indices" not in c
        for c in analysis.get("constituencies", [])
    )


def lambda_handler(event, context):
    analysis_keys = [
        k for k in io.list_output_keys("analysis/") if k.endswith(".json")
    ]
    if len(analysis_keys) < 2:
        return {"skipped": "fewer than 2 analyses present", "count": len(analysis_keys)}

    analyses = [json.loads(io.read_output_text(k)) for k in analysis_keys]
    if not any(_needs_prediction(a) for a in analyses):
        return {"skipped": "all analyses already predicted"}

    return predict.run([{"analysis_key": k} for k in analysis_keys])
