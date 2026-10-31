/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
1) Calculate active order value
2) Execute and observe a task graph
3) Process a duplicate update and verify business results
----------------------------------------------------------------------------------*/

-- 04 | Gold and observable task graph

-- Diagram: Pipeline-progression.md, Lab 04 - Task orchestration and Gold.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

-- SETUP: define the audit destination before connecting the task graph.
-- Existing SILVER.ORDERS_CURRENT holds business state; RUN_AUDIT will hold
-- one control-total snapshot per successful audit execution. It is not event history.

CREATE TABLE IF NOT EXISTS RUN_AUDIT
(
    recorded_at TIMESTAMP_LTZ,
    order_count NUMBER,
    active_amount_usd NUMBER(12, 2)
);

-- DEVELOPMENT: define the live Gold query, then connect processing and audit.

CREATE OR REPLACE VIEW GOLD.ORDER_METRICS AS
SELECT
    region,
    COUNT(*) active_orders,
    SUM(amount) active_amount_usd
FROM SILVER.ORDERS_CURRENT
WHERE status <> 'CANCELLED'
GROUP BY region;

-- Current active order value is not recognized revenue, nor sum of event amounts.

SELECT * FROM GOLD.ORDER_METRICS; -- US: 2, 150.00; no EU active orders

CREATE TASK APPLY_TASK
    WAREHOUSE = ADV_WH
    SCHEDULE = '5 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('ADV_ORDERS.BRONZE.EVENTS_STREAM')
AS
CALL ADV_ORDERS.SILVER.APPLY_EVENTS();

CREATE TASK AUDIT_TASK
    WAREHOUSE = ADV_WH
    AFTER ADV_ORDERS.OPS.APPLY_TASK
AS
INSERT INTO ADV_ORDERS.OPS.RUN_AUDIT
SELECT CURRENT_TIMESTAMP(), COUNT(*), SUM(IFF(status <> 'CANCELLED', amount, 0)) FROM ADV_ORDERS.SILVER.ORDERS_CURRENT;

-- Child must be resumed; root stays suspended, so no unattended schedule.

ALTER TASK AUDIT_TASK RESUME;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1: New event arrives after manual processing. Duplicate e8 deliberately.
-- ──────────────────────────────────────────────────────────────────────────────
-- SQL-created staged file follows the same ingest route, no local Python.

COPY INTO @BRONZE.EVENTS_STAGE/batch2/update.json.gz
FROM
(
    SELECT PARSE_JSON(column1)
    FROM VALUES
        ('{"event_id":"e8","order_id":"o3","version":3,"event_time":"2026-11-02T11:00:00Z","status":"PAID","amount":"45.00","region":"US"}'),
        ('{"event_id":"e8","order_id":"o3","version":3,"event_time":"2026-11-02T11:00:00Z","status":"PAID","amount":"45.00","region":"US"}')
)
FILE_FORMAT = (TYPE = JSON COMPRESSION = GZIP)
SINGLE = TRUE
OVERWRITE = FALSE;

-- The pipe was created with AUTO_INGEST = FALSE. This lab has no automatic
-- file-arrival notification configured, so writing a file to the stage does not
-- by itself request its loading through this pipe.
-- REFRESH manually discovers eligible files and submits them to Snowpipe's
-- ingestion queue: Snowpipe loads them asynchronously after this command returns.
-- It is a manual loading trigger, not a cloud file-arrival notification.
-- The pipe already reads @BRONZE.EVENTS_STAGE/batch2/.
-- PREFIX = 'update' restricts discovery to names beginning with 'update' under
-- that path, including the update.json.gz file we just created.
-- REFRESH checks load history; it is not a FORCE reload of an already loaded file.
-- This bounded classroom trigger is not a production polling design.
-- Source: https://docs.snowflake.com/en/sql-reference/sql/alter-pipe

ALTER PIPE BRONZE.ORDERS_PIPE REFRESH PREFIX = 'update';

-- As in lab 02, REFRESH is used only as a bounded lab recovery trigger.

SELECT COUNT(*) FROM BRONZE.EVENTS_RAW; -- wait for 10 before continuing

SELECT COUNT(*) FROM BRONZE.EVENTS_STREAM; -- 2

EXECUTE TASK APPLY_TASK;

-- EXECUTE TASK is asynchronous. Refresh history until BOTH tasks SUCCEEDED.

SELECT
    NAME,
    STATE,
    QUERY_ID,
    ERROR_CODE,
    ERROR_MESSAGE,
    SCHEDULED_TIME,
    COMPLETED_TIME
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(RESULT_LIMIT => 100))
WHERE DATABASE_NAME = 'ADV_ORDERS'
  AND SCHEMA_NAME = 'OPS'
ORDER BY SCHEDULED_TIME DESC;

SELECT * FROM RUN_AUDIT ORDER BY recorded_at DESC; -- 3 orders, active value 165

SELECT * FROM GOLD.ORDER_METRICS; -- US: 2, 165

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2: Execute again with no stream data; inspect SKIPPED/condition behavior.
-- ──────────────────────────────────────────────────────────────────────────────
-- Do not use audit row count as an exactly-once execution guarantee.

EXECUTE TASK APPLY_TASK;

-- ──────────────────────────────────────────────────────────────────────────────
-- CHECKPOINT: business result still 3 orders and active amount 165.
-- ──────────────────────────────────────────────────────────────────────────────
-- If any task fails, inspect owner privileges and query ID; do not replace tables
-- or recreate the stream. Retry only after fixing the cause and checking offsets.
-- Manual CALL SILVER.APPLY_EVENTS() is a transformation fallback, not proof
-- that the task graph succeeded. Record which path was used.
