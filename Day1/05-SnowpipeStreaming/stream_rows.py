# Snowflake Advanced 3-day class Lab 05: Snowpipe Streaming
# Copyright © 2026 Innovation In Software Corporation. All rights reserved.
"""Send 1,000 events in paced groups through a Snowpipe Streaming channel."""

from pathlib import Path
import os
import uuid
import time

from dotenv import load_dotenv

# Set the SDK log level before importing its native runtime. Keep warnings and
# errors visible; set SS_LOG_LEVEL=info in PowerShell for detailed diagnostics.
os.environ.setdefault("SS_LOG_LEVEL", "warn")
from snowflake.ingest.streaming import StreamingIngestClient

TOTAL_EVENTS = 1000
EVENTS_PER_GROUP = 100
PAUSE_SECONDS = 2


def append_events(channel, run_id):
    # These groups simulate bursts from a source. The SDK independently manages
    # network buffering/batching; a group is not a transaction or commit boundary.
    for start in range(1, TOTAL_EVENTS + 1, EVENTS_PER_GROUP):
        end = min(start + EVENTS_PER_GROUP - 1, TOTAL_EVENTS)
        for number in range(start, end + 1):
            channel.append_row(
                {
                    "RUN_ID": run_id,
                    "EVENT_NUMBER": number,
                    "PAYLOAD": {"event_id": f"demo-{number}", "status": "PLACED"},
                },
                str(number),
            )
        print(f"Appended events {start}-{end} ({end}/{TOTAL_EVENTS}); commit not yet confirmed.", flush=True)
        if end < TOTAL_EVENTS:
            time.sleep(PAUSE_SECONDS)


def required_env(name):
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"Set {name} in the repository-root .env.")
    return value


def main():
    # STEP 1: Reuse the local account/user and registered key pair from Lab 03.
    repo_root = Path(__file__).resolve().parents[2]
    load_dotenv()
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
    # Each invocation deliberately has a new channel/run ID and adds TOTAL_EVENTS rows.
    run_id = uuid.uuid4().hex
    print(f"Run ID: {run_id}", flush=True)
    print(f"Sending {TOTAL_EVENTS} events in groups of {EVENTS_PER_GROUP}, with {PAUSE_SECONDS}s pauses.", flush=True)
    print("Connecting to Snowflake and opening the streaming channel...", flush=True)

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
            append_events(channel, run_id)

            # STEP 4: Wait once for all source positions to commit.
            print(f"Waiting for Snowflake to confirm offset {TOTAL_EVENTS} committed...", flush=True)
            channel.wait_for_commit(
                lambda token: token is not None and int(token) >= TOTAL_EVENTS,
                timeout_seconds=60,
            )
            print(f"Offset {TOTAL_EVENTS} committed. Query ADV_ORDERS.STREAMING_DEMO.EVENTS in Snowflake.", flush=True)
        finally:
            channel.close()
    finally:
        client.close()


if __name__ == "__main__":
    main()
