/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
1) Prepare an isolated target for the Snowpipe Streaming lab
2) Send 1,000 rows in paced groups from local Python without creating or uploading files
3) Inspect committed rows and clean up the demo
----------------------------------------------------------------------------------*/

-- Lab 05 does not change the Day 1 pipeline or its counts.
-- Streaming ingestion uses Snowflake-managed compute; ADV_WH is for queries only.
-- CREATE fails if the name exists: verify ownership before using or dropping it.
USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;

-- STEP 1: Create a separate schema and an append-only demonstration target.
-- If the schema already exists, stop and verify ownership before proceeding.
CREATE SCHEMA STREAMING_DEMO;

USE SCHEMA STREAMING_DEMO;

CREATE TABLE EVENTS
(
    run_id STRING,
    event_number NUMBER,
    payload VARIANT
);

-- STEP 2: Suspend query compute before running the Python producer.
-- Finish Lab 04's task suspension first. Keep other worksheets, notebook sessions,
-- and data previews idle: they could independently resume the shared ADV_WH.
SHOW WAREHOUSES LIKE 'ADV_WH';
-- If state is already SUSPENDED, skip the following ALTER statement.

ALTER WAREHOUSE ADV_WH SUSPEND;
SHOW WAREHOUSES LIKE 'ADV_WH';
-- CHECKPOINT: state = SUSPENDED. Note resumed_on for comparison after ingestion.
-- SHOW WAREHOUSES does not require or resume warehouse compute.

-- PAUSE HERE. Run Day1/05-SnowpipeStreaming/stream_rows.py with local Python 3.12.
-- The SDK table-mode client uses an automatically created streaming pipe.
-- No named stage, file format, PUT command, or SQL CDC stream is needed.

-- STEP 3: After Python confirms offset 1000 committed, run ONLY this SHOW first.
SHOW WAREHOUSES LIKE 'ADV_WH';
-- CHECKPOINT: state remains SUSPENDED and resumed_on has not changed.
-- This demonstrates ingestion without resuming ADV_WH. If resumed_on changed,
-- another workload may have used it, even if it has since auto-suspended.

-- Now query the ingested rows. ADV_WH has AUTO_RESUME enabled by course setup.
-- Disable persisted-result reuse for this demonstration so the row query uses compute.
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT run_id, event_number, payload
FROM EVENTS
ORDER BY run_id, event_number
LIMIT 20; -- Sample only; the aggregate below checks every row.

SHOW WAREHOUSES LIKE 'ADV_WH';
-- CHECKPOINT: resumed_on advanced for the verification query. State should be
-- STARTED if checked promptly; auto-suspend can return it to SUSPENDED later.
     
ALTER SESSION UNSET USE_CACHED_RESULT;

SELECT run_id,
       COUNT(*)                     AS rows_in_run,
       COUNT(DISTINCT event_number) AS distinct_event_numbers,
       MIN(event_number) AS first_event, MAX(event_number) AS last_event,
       IFF(COUNT(*) = 1000 AND COUNT(DISTINCT event_number) = 1000
           AND MIN(event_number) = 1 AND MAX(event_number) = 1000,
           'PASS', 'CHECK') AS verification
FROM EVENTS
GROUP BY run_id;
-- Each completed run has 1,000 rows and 1,000 distinct event numbers (1 through 1000).
-- Each Python invocation uses a new run ID and channel: reruns add another 1,000 rows.

-- STEP 4: Inspect the streaming pipe created for this target.
SHOW PIPES IN SCHEMA ADV_ORDERS.STREAMING_DEMO;

-- STEP 5: After the client exits and results are inspected, remove only the
-- resources created by this demo. Dropping the schema also drops its pipe.
USE SCHEMA OPS;

DROP SCHEMA STREAMING_DEMO;

SHOW SCHEMAS LIKE 'STREAMING_DEMO' IN DATABASE ADV_ORDERS;
-- CHECKPOINT: no row.

-- Retain ADV_WH for the remaining course labs; no dedicated warehouse was created.
