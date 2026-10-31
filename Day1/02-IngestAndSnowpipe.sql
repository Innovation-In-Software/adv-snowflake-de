/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.

1) Load Bronze with source-file metadata
2) Distinguish file replay from duplicate business events
3) Queue a bounded Snowpipe load and inspect asynchronous completion
----------------------------------------------------------------------------------*/

-- 02 | Internal stage -> Bronze, replay, Snowpipe

-- Diagram: Pipeline-progression.md, Lab 02 - File ingestion into Bronze.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA BRONZE;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 0: Create the Bronze destination and its change-tracking stream.
-- ──────────────────────────────────────────────────────────────────────────────
-- IF NOT EXISTS makes object creation repeatable without deleting loaded data
-- or resetting the stream offset. It also preserves an existing pipe's history.
-- Existing objects keep their definitions; this is not a schema migration.
-- In a fresh environment, create both objects before the first load.
-- STEP 2 repeats COPY to demonstrate file replay. Counts below describe the
-- first pass; later runs retain the data and processing position already reached.

CREATE TABLE IF NOT EXISTS EVENTS_RAW
(
    payload VARIANT,
    source_file STRING,
    source_row NUMBER,
    scan_time TIMESTAMP_LTZ
);

-- APPEND-ONLY STREAM REFRESHER
-- EVENTS_RAW preserves delivered payloads and their file/scan lineage.
-- The append-only stream exposes inserted rows after its current offset;
-- it does not report source UPDATE or DELETE operations.
-- Our Bronze layer receives inserts, including duplicate event deliveries.
-- A stream tracks source changes, not business-event uniqueness.
-- Create it BEFORE COPY/Snowpipe inserts so those rows are available to Silver.
-- A SELECT inspects pending rows without advancing the offset.
-- Committed DML using the stream consumes its changes; Lab 03 demonstrates
-- transactional consumption into the durable Silver inbox.

CREATE STREAM IF NOT EXISTS EVENTS_STREAM
    ON TABLE EVENTS_RAW
    APPEND_ONLY = TRUE;

SELECT COUNT(*) AS pending_rows
FROM EVENTS_STREAM; -- 0 on a fresh first pass; reruns preserve the current offset

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1: Inspect semi-structured records and file lineage before loading.
-- ──────────────────────────────────────────────────────────────────────────────

SELECT
    $1,
    METADATA$FILENAME,
    METADATA$FILE_ROW_NUMBER
FROM @EVENTS_STAGE/batch1/ (FILE_FORMAT => EVENTS_JSON);

COPY INTO EVENTS_RAW
FROM
(
    SELECT $1,
           METADATA$FILENAME,
           METADATA$FILE_ROW_NUMBER,
           METADATA$START_SCAN_TIME
    FROM @EVENTS_STAGE/batch1/
)
FILE_FORMAT = EVENTS_JSON;

SELECT COUNT(*) AS raw_rows
FROM EVENTS_RAW; -- 4 on the first pass; 8 if batch2 was already loaded

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2: Repeat the exact COPY above. Expect the existing raw count unchanged.
-- ──────────────────────────────────────────────────────────────────────────────
-- File-load history is NOT business-key deduplication: e2 still occurs twice.

SELECT
    payload:event_id::STRING AS event_id,
    COUNT(*) AS copies
FROM EVENTS_RAW
GROUP BY 1
ORDER BY 1;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3: Define Snowpipe for the second batch only; do NOT bulk COPY batch2.
-- ──────────────────────────────────────────────────────────────────────────────

CREATE PIPE IF NOT EXISTS ORDERS_PIPE
    AUTO_INGEST = FALSE
AS
COPY INTO ADV_ORDERS.BRONZE.EVENTS_RAW
FROM
(
    SELECT $1,
           METADATA$FILENAME,
           METADATA$FILE_ROW_NUMBER,
           METADATA$START_SCAN_TIME
    FROM @ADV_ORDERS.BRONZE.EVENTS_STAGE/batch2/
)
FILE_FORMAT = ADV_ORDERS.BRONZE.EVENTS_JSON
ON_ERROR = SKIP_FILE;

-- This is a bounded recovery/backfill exercise, NOT continuous scheduling.
-- REFRESH queues recently staged files (7-day limit); ingestion is asynchronous.

ALTER PIPE ORDERS_PIPE REFRESH;

-- HOW TO READ PIPE STATUS
-- executionState = RUNNING is normal, including when no files are being loaded.
-- This is the pipe's operating state, not a batch-progress status.
-- Do not wait for COMPLETED after the rows arrive; RUNNING can remain unchanged.
-- pendingFileCount counts queued files; expect 0 when this bounded queue drains.
-- A zero queue alone does not prove the expected files loaded successfully.
-- lastIngestedFilePath / lastIngestedTimestamp identify the latest successful load
-- when those fields are present. For this exercise, inspect the batch2 file.
-- PAUSED or STOPPED_/STALLED_ states need investigation if loading is expected.
-- Read error / fault details when present; a recorded last error may be historical.
-- Source: https://docs.snowflake.com/en/sql-reference/functions/system_pipe_status

SELECT SYSTEM$PIPE_STATUS('ADV_ORDERS.BRONZE.ORDERS_PIPE');

SELECT COUNT(*) AS raw_rows
FROM EVENTS_RAW; -- eventually 8

SELECT
    FILE_NAME,
    STATUS,
    ROW_COUNT,
    ERROR_COUNT,
    FIRST_ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'ADV_ORDERS.BRONZE.EVENTS_RAW',
    START_TIME => DATEADD('hour', -1, CURRENT_TIMESTAMP())
));

-- ──────────────────────────────────────────────────────────────────────────────
-- CHECKPOINT: 8 raw rows, 2 loaded files. Wait/requery for up to 5 minutes.
-- Confirm the expected batch1 and batch2 paths in COPY_HISTORY:
-- STATUS = Loaded, ROW_COUNT = 4 per file, ERROR_COUNT = 0.
-- Batch1 was bulk-loaded; batch2 was loaded by this pipe. Total raw_rows = 8.
-- RUNNING with pendingFileCount = 0 is compatible with this completed load.
-- If history has not appeared yet, wait/requery; row count alone is insufficient.
-- ──────────────────────────────────────────────────────────────────────────────
-- If not reached: inspect pipe status/history; record query IDs and errors.
-- Stop here instead of claiming success. The documented fallback in the guide
-- deliberately abandons this pipe branch before bulk loading batch2.
-- Parseable JSON can still violate business rules (e3). Bronze preserves it.

SELECT COUNT(*) AS pending_rows
FROM EVENTS_STREAM; -- 8 before Lab 03 consumes them; 0 after its successful commit

SELECT COUNT(*) AS pending_rows
FROM EVENTS_STREAM; -- unchanged by the preceding SELECT
