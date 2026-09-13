# Build context is the repo root (set in CDK DockerImageCode.from_image_asset).
FROM public.ecr.aws/lambda/python:3.12

COPY apps/ml_pipeline/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY src/curia_core ${LAMBDA_TASK_ROOT}/curia_core
COPY apps/ml_pipeline/app.py ${LAMBDA_TASK_ROOT}/

CMD ["app.lambda_handler"]
