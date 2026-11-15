# Lab 05: Snowpipe Streaming

Run after Lab 04. This lab sends 1,000 events directly from local Python
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

For additional background on integrating a real event source, see
[Kafka integration pseudocode](Kafka-Pseudocode.md). This conceptual example
is optional reading, not an additional exercise or runnable script.

## Before class

- Complete [student VM setup](../../SetUp/README.md) to install the local
  course dependencies. The pinned SDK
  version is intentional; rehearse again before changing it.
- The repository-root `.env` must contain `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`,
  and `SNOWFLAKE_PRIVATE_KEY_FILE`. The public key must be registered for that
  user, and the user must have the `ADV_LAB` role. Relative key paths are
  resolved from the repository root. Existing environment variables take
  precedence over `.env`; keep credentials and private keys out of Git.
- The role needs permission to create a schema in `ADV_ORDERS` and operate
  the existing `ADV_WH`, as granted by course setup. The local machine needs network access to
  Snowflake's account and streaming endpoints and storage destinations.
- The warehouse, streaming ingestion, and storage incur charges. Use only a
  dedicated training account and resources.

The producer sends ten groups of 100 events, pausing two seconds between groups
(18 seconds of pauses, plus connection and commit time). These source groups
are not SDK network batches or transactions. `TOTAL_EVENTS`, `EVENTS_PER_GROUP`,
and `PAUSE_SECONDS` in the producer control the demonstration. If you change
`TOTAL_EVENTS`, adjust the SQL expected counts accordingly. Keep verification
queries until after the suspended-warehouse checkpoint.

## Exercise

1. In `05-Setup-and-Verify.sql`, execute the session context and Step 1.
   The names must be unused; if creation fails, stop and check ownership.
   In Step 2, suspend `ADV_WH` if it is running and verify `SUSPENDED` with
   `SHOW WAREHOUSES`. Finish Lab 04's task suspension and keep other workloads idle.
2. From the repository root, run:

   ```powershell
   & "$HOME\.venvs\adv-snowflake-de\Scripts\python.exe" .\Day1\05-SnowpipeStreaming\stream_rows.py
   ```

3. Note the printed run ID. `append_row` is not a commit; wait for the
   message that offset 1000 committed. The program closes its channel and client.
4. In Step 3, first run only `SHOW WAREHOUSES`: expect `ADV_WH` still suspended
   with an unchanged `resumed_on`. This metadata command does not resume it.
   Then run the verification queries, which use `ADV_WH` and trigger auto-resume.
   For that run ID, expect event numbers 1 through 1000,
   1,000 rows and 1,000 distinct event numbers. Each `PAYLOAD` is a JSON object.
   Step 4 shows the default streaming pipe.
5. After inspecting the results, run Step 5 to drop the lab schema.
   Retain `ADV_WH` for the remaining labs. If stopping early, remove only resources this lab
   actually created; do not drop an existing resource with the same name.

Each invocation creates a new run ID and channel and intentionally adds 1,000
rows. This lab does **not** implement restart recovery or event deduplication.
For exactly-once recovery with a named channel, a real producer must resume
from the last committed offset using a durable replayable source.

If the producer fails or times out, inspect the printed run ID in Snowflake
before retrying: a timeout does not prove that no rows arrived. A memory
throttling error can mean the local machine is under memory pressure; free
memory or use another machine and retry after checking the target.

## Console output

The producer defaults to SDK log level `warn`, keeping warnings and errors
visible while hiding routine SDK initialization and shutdown messages. A
successful run shows the run ID, connection progress, ten progress messages (100 events each),
and confirmation that offset 1000 committed. Appending alone is not confirmation.

For troubleshooting, enable detailed SDK logs before running the producer:

```powershell
$env:SS_LOG_LEVEL = 'info'
```

Return to concise output with:

```powershell
$env:SS_LOG_LEVEL = 'warn'
```

These settings apply to Python processes launched from that PowerShell session.
Each producer execution still adds a new set of 1,000 rows.

## Rehearsal status

The earlier three-event version was verified live; the new paced 1,000-event
version still needs live rehearsal. Live QA with SDK 1.9.3 committed all three rows, returned three native JSON
objects, displayed the managed `EVENTS-STREAMING` pipe, and removed the QA
schema and the then-used dedicated warehouse. The revised suspended-`ADV_WH`
checkpoints still require a live rehearsal. The producer took about 24 seconds on that run. Earlier
attempts were blocked by local memory pressure; rehearse on the presentation
machine and network before class.

References: [Named Channels SDK tutorial](https://docs.snowflake.com/en/user-guide/snowpipe-streaming/snowpipe-streaming-high-performance-getting-started),
[network prerequisites](https://docs.snowflake.com/en/user-guide/snowpipe-streaming/snowpipe-streaming-network-connectivity).
