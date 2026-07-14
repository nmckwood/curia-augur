"""ML pipeline lambda handler (container image), triggered by S3 ObjectCreated on the
ingestion output prefix. Thin wrapper over curia_core.ml.pipeline.
"""

from curia_core.ml import pipeline


def lambda_handler(event, context):
    return pipeline.run(event)
