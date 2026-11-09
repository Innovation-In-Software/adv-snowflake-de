# Snowflake Advanced 3-day class Lab: instructor Snowpipe Streaming demo
# Copyright © 2026 Innovation In Software Corporation. All rights reserved.
"""Send three rows directly through a Snowpipe Streaming named channel."""

from pathlib import Path
import os
import uuid

from dotenv import load_dotenv
from snowflake.ingest.streaming import StreamingIngestClient


def required_env(name):
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"Set {name} in the repository-root .env.")
    return value


def main():
    # STEP 1: Reuse the local account/user and registered key pair from Lab 02A.
    repo_root = Path(__file__).resolve().parents[2]
    load_dotenv(repo_root / ".env", override=False)
    account = required_env("SNOWFLAKE_ACCOUNT")
    key_path = Path(required_env("SNOWFLAKE_PRIVATE_KEY_FILE")).expanduser()
    if not key_path.is_absolute():
        key_path = (repo_root / key_path).resolve()
    properties = {
        "account": account,
        "url": f"https://{account}.snowflakecomputing.com:443",
        "user": required_env("SNOWFLAKE_USER"),
        "private_key_file": str(key_path),
        "role": "ADV_LAB",
    }

    # STEP 2: Open a channel to the isolated table. The SDK handles authentication.
    # Table mode uses the target's default streaming pipe; it does not use ORDERS_PIPE.
    # Each invocation deliberately has a new channel/run ID and adds three rows.
    run_id = uuid.uuid4().hex
    print(f"Run ID: {run_id}")
    client = StreamingIngestClient.from_table(
        client_name="advanced-class-streaming-demo",
        db_name="ADV_ORDERS",
        schema_name="STREAMING_DEMO",
        table_name="EVENTS",
        properties=properties,
    )
    try:
        channel, _ = client.open_channel("DEMO_" + run_id, "0")
        try:
            # STEP 3: Append native Python objects. No JSON file or PUT is involved.
            # The SDK buffers/transmits asynchronously. Tokens track source positions
            # within this channel; they are not business-event deduplication keys.
            for number in range(1, 4):
                channel.append_row(
                    {
                        "RUN_ID": run_id,
                        "EVENT_NUMBER": number,
                        "PAYLOAD": {"event_id": f"demo-{number}", "status": "PLACED"},
                    },
                    str(number),
                )
                print(f"Appended event {number}; awaiting commit at the final checkpoint.")

            # STEP 4: Wait once for all three source positions to commit.
            channel.wait_for_commit(
                lambda token: token is not None and int(token) >= 3,
                timeout_seconds=60,
            )
            print("Offset 3 committed. Query ADV_ORDERS.STREAMING_DEMO.EVENTS in Snowflake.")
        finally:
            channel.close()
    finally:
        client.close()


if __name__ == "__main__":
    main()
