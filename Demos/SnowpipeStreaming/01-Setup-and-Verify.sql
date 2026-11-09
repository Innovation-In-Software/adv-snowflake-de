/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
1) Prepare an isolated target for an instructor Snowpipe Streaming rehearsal
2) Send three rows from local Python without creating or uploading files
3) Inspect the committed rows before deciding whether to add this to the course
----------------------------------------------------------------------------------*/

-- Instructor demo only; this does not change the Day 1 pipeline or its counts.
USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;

-- STEP 1: Create a separate schema and an append-only demonstration target.
CREATE SCHEMA IF NOT EXISTS STREAMING_DEMO;
USE SCHEMA STREAMING_DEMO;
CREATE TABLE IF NOT EXISTS EVENTS
(
    run_id STRING,
    event_number NUMBER,
    payload VARIANT
);

-- STEP 2: PAUSE HERE. Run Demos/SnowpipeStreaming/stream_rows.py with local Python 3.12.
-- The SDK table-mode client uses an automatically created streaming pipe.
-- No named stage, file format, PUT command, or SQL CDC stream is needed.

-- STEP 3: Rerun these queries after the producer confirms offset 3 committed.
SELECT run_id, event_number, payload
FROM EVENTS
ORDER BY run_id, event_number;

SELECT run_id, COUNT(*) AS rows_in_run,
       COUNT(DISTINCT event_number) AS distinct_event_numbers
FROM EVENTS
GROUP BY run_id;
-- Each completed run has 3 rows and 3 distinct event numbers.
-- Each Python invocation uses a new run ID and channel: reruns add another 3 rows.

-- STEP 4: Inspect the streaming pipe created for this target.
SHOW PIPES IN SCHEMA ADV_ORDERS.STREAMING_DEMO;

-- Optional cleanup AFTER the Python client exits and results are inspected:
-- DROP SCHEMA ADV_ORDERS.STREAMING_DEMO;
