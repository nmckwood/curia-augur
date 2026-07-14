# Build context is the repo root (set in CDK DockerImageCode.from_image_asset).
FROM public.ecr.aws/lambda/python:3.11

COPY apps/data_ingestion/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Functional core shared with the local /tools runners.
COPY src/curia_core ${LAMBDA_TASK_ROOT}/curia_core
COPY apps/data_ingestion/app.py ${LAMBDA_TASK_ROOT}/

CMD ["app.lambda_handler"]
