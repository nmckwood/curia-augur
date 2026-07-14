"""Upload the raw input data files to the S3 input bucket (REQ Data-Ingestion-2).

Usage:
    python tools/upload_data_to_s3.py --bucket <input-bucket> [--data-dir ./data]

Uploads deprivation, election and geospatial files with their basename as the key so
the ingestion event can reference them by filename.
"""

import argparse
import os

import boto3


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True)
    parser.add_argument(
        "--data-dir",
        default=os.path.join(os.path.dirname(__file__), "..", "data"),
    )
    args = parser.parse_args()

    s3 = boto3.client("s3")
    for root, _dirs, files in os.walk(args.data_dir):
        for name in files:
            path = os.path.join(root, name)
            print(f"uploading {name} -> s3://{args.bucket}/{name}")
            s3.upload_file(path, args.bucket, name)
    print("done")


if __name__ == "__main__":
    main()
