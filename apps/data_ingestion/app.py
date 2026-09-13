"""
Data ingestion lambda handler

Thin wrapper: all logic lives in curia_core.ingestion.pipeline 
so the exact same code runs locally via tools/run_ingestion_local.py,
"""

from curia_core.ingestion import pipeline


def lambda_handler(event, context):
    return pipeline.run(event)
