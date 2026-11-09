# Instructor rehearsal: Snowpipe Streaming

This is a small experiment for deciding whether Streaming belongs in the course. It is not a numbered student lab and does not alter EVENTS_RAW, Silver, or Gold.

## What changes from 02A?

- 02A writes a local JSON file, uploads it to a stage, then submits its filename to ORDERS_PIPE.
- This demo passes three Python dictionaries to a Snowpipe Streaming SDK channel. The SDK handles transmission and buffering. There are no application-created data files or PUT commands.
- A channel is an ingestion connection with source-offset tracking; it is different from the SQL STREAM objects used to track table/directory changes.
- Table mode uses a default streaming pipe created for EVENTS. This is separate from the existing file-ingestion ORDERS_PIPE.

## Five-minute walkthrough

1. Pull the repository locally and in your Snowflake workspace.
2. Use your **local Python 3.12** environment, with the existing repository-root .env and registered private key. This is not a Snowflake-hosted Python worksheet.
3. In Snowflake, execute Step 1 of `01-Setup-and-Verify.sql` as ADV_LAB, then pause. It creates only the isolated STREAMING_DEMO schema and EVENTS table.
4. In a local terminal using that Python environment:

```powershell
python --version
python -m pip install --upgrade -r Demos/SnowpipeStreaming/requirements.txt
python Demos/SnowpipeStreaming/stream_rows.py
```

If `python --version` is not your 3.12 interpreter, select your 3.12 environment or use its full executable path for both commands. The SDK requires Python 3.9 or later. This demo uses the current SDK's `from_table` and `wait_for_commit` APIs.

5. Read the producer output: appended is not yet committed. It prints success only after offset 3 is committed. Run the verification SQL: expect three rows for that run ID, with native JSON objects in PAYLOAD.
6. Run Python again if desired: a new run ID/channel intentionally adds another three rows. This demo does not implement restart recovery or business-event deduplication. A production named-channel producer resumes a durable source from its last committed offset; simply choosing a new channel does not provide exactly-once recovery.

A timeout is not proof that nothing arrived: inspect rows for the printed run ID before retrying. The client closes its channel and connection on exit. No scheduled task is created. The optional schema cleanup is commented out in the SQL.

## Rehearsal status

Prepared against official SDK documentation; local syntax and mocked control-flow checks only. Live SDK authentication, network access, commit timing, and SQL verification remain to be rehearsed in your account. No real credentials are included. Record the SDK version (`python -m pip show snowpipe-streaming`), elapsed time, and observed row counts before adopting the demo for students.

References: [Named Channels SDK tutorial](https://docs.snowflake.com/en/user-guide/snowpipe-streaming/snowpipe-streaming-high-performance-getting-started), [Python client API](https://docs.snowflake.com/en/user-guide/snowpipe-streaming-sdk-python/reference/latest/api/snowflake/ingest/streaming/streaming_ingest_client/index).
