-- Optional 02A: reuse Lab 02 objects; no new stage, pipe, or target.
-- The REST API uses the user's DEFAULT_ROLE, not the connector's session role.
-- Run as the same training user configured in the local .env.
USE ROLE ACCOUNTADMIN;
SET student_user = CURRENT_USER();
ALTER USER IDENTIFIER($student_user) SET DEFAULT_ROLE = ADV_LAB;

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA BRONZE;


-- ADV_LAB owns ORDERS_PIPE and has the required database/schema access.
SELECT GET_DDL('PIPE', 'ADV_ORDERS.BRONZE.ORDERS_PIPE');

DESCRIBE PIPE ORDERS_PIPE;

-- Confirm AUTO_INGEST=FALSE and source @EVENTS_STAGE/batch2/.
SELECT SYSTEM$PIPE_STATUS('ADV_ORDERS.BRONZE.ORDERS_PIPE');

ALTER PIPE ADV_ORDERS.BRONZE.ORDERS_PIPE  SET LOG_EVENT_LEVEL = DEBUG;

-- If deliberately paused by 99-Stop.sql, resume before running the client:
-- ALTER PIPE ORDERS_PIPE SET PIPE_EXECUTION_PAUSED = FALSE;
SELECT COUNT(*) AS raw_rows FROM EVENTS_RAW; -- 8 before 02A; 12 after
SELECT COUNT(*) AS pending_rows FROM EVENTS_STREAM; -- 8 before; 12 after, before Lab 03


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

ALTER PIPE ADV_ORDERS.BRONZE.ORDERS_PIPE  SET LOG_EVENT_LEVEL = OFF;