-- Lab 02A: submit a new file to the existing pipe through the Snowpipe REST API.
-- Run this worksheet in sections; keep it open while running Python locally.
-- Reuse EVENTS_STAGE, ORDERS_PIPE, and EVENTS_RAW from Lab 02.
-- STEP 1: Set the training user's default role for REST API requests.
-- The REST API uses the user's DEFAULT_ROLE, not the connector's session role.
-- Run as the same training user configured in the local .env.
USE ROLE ACCOUNTADMIN;
SET student_user = CURRENT_USER();
ALTER USER IDENTIFIER($student_user) SET DEFAULT_ROLE = ADV_LAB;

-- STEP 2: Inspect the pipe and enable file-level telemetry.
USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA BRONZE;


-- ADV_LAB owns ORDERS_PIPE and has the required database/schema access.
SELECT GET_DDL('PIPE', 'ADV_ORDERS.BRONZE.ORDERS_PIPE');

DESCRIBE PIPE ORDERS_PIPE;

-- Confirm AUTO_INGEST=FALSE and source @EVENTS_STAGE/batch2/ in the definition above.
-- RUNNING below is the pipe operating state, not proof that a file loaded.
SELECT SYSTEM$PIPE_STATUS('ADV_ORDERS.BRONZE.ORDERS_PIPE');

-- Enable BEFORE running Python to record received, loaded, and skipped files.
-- ADV_LAB uses the MODIFY LOG EVENT LEVEL grant from environment setup.
ALTER PIPE ADV_ORDERS.BRONZE.ORDERS_PIPE SET LOG_EVENT_LEVEL = DEBUG;

-- If deliberately paused by 99-Stop.sql, resume before running the client:
-- ALTER PIPE ORDERS_PIPE SET PIPE_EXECUTION_PAUSED = FALSE;
SELECT COUNT(*) AS raw_rows FROM EVENTS_RAW; -- 8 before 02A; 12 after
SELECT COUNT(*) AS pending_rows FROM EVENTS_STREAM; -- 8 before; 12 after, before Lab 03


-- STEP 3: PAUSE HERE. Run locally from the repository root:
-- python Day1/02A-PythonSnowpipe.py
-- Then rerun the counts above: 12 raw and 12 pending before Lab 03.
-- Run Python again with the same filename; both counts should stay at 12.

-- STEP 4: Inspect file loads from the last 24 hours.
-- PIPE_NAME is NULL for direct COPY; ORDERS_PIPE identifies Snowpipe loads.
-- This history does not label REFRESH versus REST submissions.
-- A repeated, skipped submission does not imply another successful file load.
SELECT
    file_name,
    pipe_name,
    status,
    row_count,
    pipe_received_time,
    last_load_time,
    first_error_message
FROM TABLE(
    ADV_ORDERS.INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'ADV_ORDERS.BRONZE.EVENTS_RAW',
        START_TIME => DATEADD('hour', -24, CURRENT_TIMESTAMP())
    )
)
ORDER BY last_load_time DESC;


-- STEP 5: Inspect file lifecycle events, including skipped submissions.
-- DEBUG logging must have been enabled before the request; events may take
-- time to appear. This is file-level telemetry, not one row per HTTP call.
-- Query the configured event table if your account uses a different one.
-- Event timestamps and SYSDATE() use UTC.
SELECT
    timestamp,
    record_attributes:"snow.file.path"::STRING AS file_name,
    PARSE_JSON(value):state::STRING AS state,
    value AS details
FROM SNOWFLAKE.TELEMETRY.EVENTS
WHERE record_type = 'EVENT'
  AND record:"name" = 'file_lifecycle'
  AND resource_attributes:"snow.database.name" = 'ADV_ORDERS'
  AND resource_attributes:"snow.schema.name" = 'BRONZE'
  AND resource_attributes:"snow.pipe.name" = 'ORDERS_PIPE'
  AND timestamp >= DATEADD('hour', -1, SYSDATE())
ORDER BY timestamp DESC;

-- STEP 6: Run after inspecting BOTH the initial Python run and the rerun.
-- Turn detailed logging off; this does not pause the pipe.
ALTER PIPE ADV_ORDERS.BRONZE.ORDERS_PIPE SET LOG_EVENT_LEVEL = OFF;