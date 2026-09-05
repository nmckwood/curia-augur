"""Files API lambda handler (zip, boto3 only).

GET returns presigned URLs for every ML analysis output (REQ APIs-1). API Gateway's
Cognito authorizer gates access (REQ UI-8); this handler also refuses unauthenticated
requests defensively and returns appropriate status codes (REQ APIs-2).
"""

import json
import os

import boto3

s3 = boto3.client("s3")

OUTPUT_BUCKET = os.environ["OUTPUT_BUCKET"]
ANALYSIS_PREFIX = os.environ.get("ANALYSIS_PREFIX", "analysis/")
URL_TTL_SECONDS = int(os.environ.get("URL_TTL_SECONDS", "3600"))

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
}


def _response(status, body):
    return {"statusCode": status, "headers": CORS_HEADERS, "body": json.dumps(body)}


def _is_authenticated(event):
    context = event.get("requestContext", {})
    authorizer = context.get("authorizer") or {}
    claims = authorizer.get("claims") or authorizer.get("jwt", {}).get("claims")
    return bool(claims)


def lambda_handler(event, context):
    """
    authenticate a user and return a pre signed url to the browser to then fetch the data
    """
    if not _is_authenticated(event):
        return _response(401, {"message": "unauthorized"})
    
    try:
        paginator = s3.get_paginator("list_objects_v2")
        items = []
        for page in paginator.paginate(Bucket=OUTPUT_BUCKET, Prefix=ANALYSIS_PREFIX):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                if not key.endswith(".json"):
                    continue
                url = s3.generate_presigned_url(
                    "get_object",
                    Params={"Bucket": OUTPUT_BUCKET, "Key": key},
                    ExpiresIn=URL_TTL_SECONDS,
                )
                items.append(
                    {"filename": os.path.basename(key), "pre_signed_url": url}
                )
        if not items:
            return _response(404, {"message": "no analysis outputs available"})
        return _response(200, items)
    except Exception as exc:  # noqa: BLE001 - surface a 500 with a safe message
        return _response(500, {"message": "internal error", "detail": str(exc)})
