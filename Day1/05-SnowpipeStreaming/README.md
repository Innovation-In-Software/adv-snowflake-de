# Lab 05: Snowpipe Streaming

Run after Lab 04. This lab sends three events directly from local Python
to a separate Snowflake table; it does not change the Day 1 pipeline or counts.
Run the numbered steps rather than executing the SQL file all at once.

## What students should notice

Lab 03 creates a file, uploads it to a stage, and submits its name to
`ORDERS_PIPE`. Here the application appends Python dictionaries to a Snowpipe
Streaming **named channel**, waits for a committed offset, and queries the
table. No application-created file, PUT, or file-ingestion pipe is used.
The SDK can use internal buffering and files.

A channel tracks source positions; it is not a SQL `STREAM` object. Table mode
uses a default streaming pipe, separate from `ORDERS_PIPE`.

## Before class

- Use local Python 3.12 and install the dependencies below. The pinned SDK
  version is intentional; rehearse again before changing it.
- The repository-root `.env` must contain `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`,
  and `SNOWFLAKE_PRIVATE_KEY_FILE`. The public key must be registered for that
  user, and the user must have the `ADV_LAB` role. Relative key paths are
  resolved from the repository root. Existing environment variables take
  precedence over `.env`; keep credentials and private keys out of Git.
- The role needs permission to create a schema in `ADV_ORDERS`. `ACCOUNTADMIN`
  creates the dedicated warehouse. The local machine needs network access to
  Snowflake's account and streaming endpoints and storage destinations.
- The warehouse, streaming ingestion, and storage incur charges. Use only a
  dedicated training account and resources.

From the repository root, install once:

```powershell
python -m pip install -r Day1\05-SnowpipeStreaming\requirements.txt
python -m pip show snowpipe-streaming
```

## Exercise

1. In `05-Setup-and-Verify.sql`, execute the warehouse setup and Step 1.
   The names must be unused; if creation fails, stop and check ownership.
2. From the repository root, run:

   ```powershell
   python Day1\05-SnowpipeStreaming\stream_rows.py
   ```

3. Note the printed run ID. `append_row` is not a commit; wait for the
   message that offset 3 committed. The program closes its channel and client.
4. Run Step 3 in SQL. For that run ID, expect event numbers 1, 2, and 3,
   three rows and three distinct event numbers. Each `PAYLOAD` is a JSON object.
   Step 4 shows the default streaming pipe.
5. After inspecting the results, run Step 5 to drop the lab schema and
   dedicated warehouse. If stopping early, remove only resources this lab
   actually created; do not drop an existing resource with the same name.

Each invocation creates a new run ID and channel and intentionally adds three
rows. This lab does **not** implement restart recovery or event deduplication.
For exactly-once recovery with a named channel, a real producer must resume
from the last committed offset using a durable replayable source.

If the producer fails or times out, inspect the printed run ID in Snowflake
before retrying: a timeout does not prove that no rows arrived. A memory
throttling error can mean the local machine is under memory pressure; free
memory or use another machine and retry after checking the target.

## Rehearsal status

Live QA with SDK 1.9.3 committed all three rows, returned three native JSON
objects, displayed the managed `EVENTS-STREAMING` pipe, and removed the QA
schema and warehouse. The producer took about 24 seconds on that run. Earlier
attempts were blocked by local memory pressure; rehearse on the presentation
machine and network before class.

References: [Named Channels SDK tutorial](https://docs.snowflake.com/en/user-guide/snowpipe-streaming/snowpipe-streaming-high-performance-getting-started),
[network prerequisites](https://docs.snowflake.com/en/user-guide/snowpipe-streaming/snowpipe-streaming-network-connectivity).
