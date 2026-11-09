-- Lab 02B | Directory table stream + triggered task
-- Run after Labs 01-02. This branch uses an isolated stage and target and does
-- not change EVENTS_RAW or the expected starting state for Lab 03.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA BRONZE;

CREATE FILE FORMAT IF NOT EXISTS DIR_EVENTS_JSON
    TYPE = JSON
    COMPRESSION = AUTO;

CREATE STAGE IF NOT EXISTS DIR_EVENTS_STAGE
    DIRECTORY = (ENABLE = TRUE) -- this creates a directory table that we can query 
    FILE_FORMAT = DIR_EVENTS_JSON;

SELECT *
FROM DIRECTORY(@DIR_EVENTS_STAGE);

CREATE TABLE IF NOT EXISTS DIR_EVENTS_RAW
(
    payload VARIANT,
    source_file STRING,
    source_row NUMBER,
    scan_time TIMESTAMP_LTZ
);

-- This table serves as an audit trail and the destination for consuming stream changes.
CREATE TABLE IF NOT EXISTS DIR_FILE_EVENTS
(
    relative_path STRING,
    file_size NUMBER,
    last_modified TIMESTAMP_LTZ,
    observed_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- This is a stream on the the stage's DIRECTORY table 
CREATE STREAM IF NOT EXISTS DIR_EVENTS_STAGE_STREAM
    ON STAGE DIR_EVENTS_STAGE;

CREATE OR REPLACE PROCEDURE SP_LOAD_DIRECTORY_STAGE_FILES()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
    -- This INSERT consumes the directory-table stream and records the observed
    -- file metadata. The subsequent COPY scans the isolated stage; Snowflake's
    -- COPY load metadata skips files already loaded into this target table.
    INSERT INTO DIR_FILE_EVENTS (relative_path, file_size, last_modified)
    SELECT RELATIVE_PATH, SIZE, LAST_MODIFIED::TIMESTAMP_LTZ
    FROM DIR_EVENTS_STAGE_STREAM
    WHERE METADATA$ACTION = 'INSERT';

    COPY INTO DIR_EVENTS_RAW
    FROM
    (
        SELECT $1,
               METADATA$FILENAME,
               METADATA$FILE_ROW_NUMBER,
               METADATA$START_SCAN_TIME
        FROM @DIR_EVENTS_STAGE
    )
    FILE_FORMAT = DIR_EVENTS_JSON
    ON_ERROR = SKIP_FILE;

    RETURN 'Directory stream consumed; COPY INTO completed. Review DIR_FILE_EVENTS and COPY_HISTORY.';
END;
$$;

CREATE TASK IF NOT EXISTS DIR_EVENTS_LOAD_TASK
    WAREHOUSE = ADV_WH
    WHEN SYSTEM$STREAM_HAS_DATA('DIR_EVENTS_STAGE_STREAM')
    AS CALL SP_LOAD_DIRECTORY_STAGE_FILES();

-- Resume only after the stage, stream, table, and procedure exist.
ALTER TASK DIR_EVENTS_LOAD_TASK RESUME;

-- Mimic file upload to @DIR_EVENTS_STAGE from the local client:

COPY INTO @DIR_EVENTS_STAGE/batch1/events.json
FROM (SELECT payload FROM VW_ORDER_EVENTS_SOURCE WHERE batch = 1)
SINGLE = TRUE OVERWRITE = TRUE;

COPY INTO @DIR_EVENTS_STAGE/batch2/events.json
FROM (SELECT payload FROM VW_ORDER_EVENTS_SOURCE WHERE batch = 2)
SINGLE = TRUE OVERWRITE = TRUE;

-- then refresh directory metadata to make the changes visible to the stream:
ALTER STAGE DIR_EVENTS_STAGE REFRESH;

-- Check directory table again:
SELECT *
FROM DIRECTORY(@DIR_EVENTS_STAGE);

-- The triggered task should then copy the files into DIR_EVENTS_RAW.

SELECT SYSTEM$STREAM_HAS_DATA('DIR_EVENTS_STAGE_STREAM') AS has_pending_file_changes;

SELECT * FROM DIR_FILE_EVENTS ORDER BY observed_at DESC;

SELECT COUNT(*) AS directory_branch_rows FROM DIR_EVENTS_RAW;


SELECT
    name,
    state,
    scheduled_from,
    scheduled_time,
    query_start_time,
    completed_time,
    error_message
FROM TABLE(
    ADV_ORDERS.INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'DIR_EVENTS_LOAD_TASK',
        SCHEDULED_TIME_RANGE_START =>
            DATEADD('hour', -1, CURRENT_TIMESTAMP()),
        RESULT_LIMIT => 100
    )
)
ORDER BY scheduled_time DESC;
