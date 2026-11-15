"""Verify optional AWS credentials with a read-only STS identity request."""

import os

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from dotenv import load_dotenv


def main() -> None:
    if not load_dotenv(override=False):
        raise SystemExit("Could not find .env. Copy .env.example to the repository root.")

    access_key = os.getenv("AWS_ACCESS_KEY_ID", "").strip()
    secret_key = os.getenv("AWS_SECRET_ACCESS_KEY", "").strip()
    access_missing = not access_key or access_key == "YOUR_ACCESS_KEY_ID"
    secret_missing = not secret_key or secret_key == "YOUR_SECRET_ACCESS_KEY"

    if access_missing and secret_missing:
        print("AWS connection check skipped: no AWS credentials configured.")
        return
    if access_missing or secret_missing:
        raise SystemExit("Set both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY in .env.")

    region = os.getenv("AWS_DEFAULT_REGION", "us-east-2").strip()
    if not region:
        raise SystemExit("Set AWS_DEFAULT_REGION to a valid AWS region or leave it unset.")
    token = os.getenv("AWS_SESSION_TOKEN", "").strip() or None

    try:
        session = boto3.Session(
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            aws_session_token=token,
            region_name=region,
        )
        sts = session.client(
            "sts",
            config=Config(connect_timeout=10, read_timeout=10, retries={"max_attempts": 2}),
        )
        identity = sts.get_caller_identity()
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "Unknown")
        raise SystemExit(
            f"AWS connection failed ({code}). Check credentials, session token, region, "
            "and network access."
        ) from None
    except BotoCoreError as exc:
        raise SystemExit(
            f"AWS connection failed ({type(exc).__name__}). Check credentials, session token, "
            "region, and network access."
        ) from None

    print("AWS connection confirmed.")
    print(f"Account: {identity['Account']} | Identity: {identity['Arn']}")
    print("This check does not verify permissions for Lab 21.")


if __name__ == "__main__":
    main()
