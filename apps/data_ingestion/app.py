"""Data ingestion lambda handler (container image).

Thin wrapper: all logic lives in curia_core.ingestion.pipeline so the exact same code
runs locally via tools/run_ingestion_local.py. Invoked directly with the REQ
Data-Ingestion-3 event shape.
"""

from curia_core.ingestion import pipeline


def lambda_handler(event, context):
    return pipeline.run(event)
