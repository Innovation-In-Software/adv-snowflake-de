/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
Day 2 shutdown — preserve data and stop scheduled compute
1) Suspend Dynamic Table refresh and course tasks
2) Stop the lab data metric schedule and ingestion
3) Preserve governed Gold for Day 3
----------------------------------------------------------------------------------*/

-- REQUIRED END-OF-DAY STEP: every student runs this file before leaving.
-- Closing the browser or worksheet does not suspend background objects.
-- ADV_WH has AUTO_SUSPEND=60 and AUTO_RESUME=TRUE: idle compute can sleep,
-- but later task/refresh queries can wake it and incur another billed startup.
-- Main APPLY_TASK is normally left suspended in the labs. A scheduled task whose
-- WHEN condition is false does not resume its warehouse, although condition
-- evaluation has cloud-services overhead. Do not assume every enabled task
-- keeps a warehouse running continuously.
-- Snowpipe loads are billed separately from ADV_WH; warehouse suspension alone
-- does not pause a pipe. No pending/new loads does not mean idle Snowpipe billing
-- continues indefinitely: we pause it to prevent further unintended ingestion.
-- Days 2-3 add refresh/maintenance services: stop those explicitly as shown below.
-- End active notebook sessions using their controls if a notebook was used.
-- Preserved tables/stage files still incur storage charges after compute stops.
-- Sources:
-- https://docs.snowflake.com/en/user-guide/tasks-intro
-- https://docs.snowflake.com/en/sql-reference/sql/create-task
-- https://docs.snowflake.com/en/user-guide/data-load-snowpipe-billing

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY2';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Stop the explicit background objects created by the course
-- ──────────────────────────────────────────────────────────────────────────────

USE ROLE ADV_LAB;
USE SECONDARY ROLES NONE;

ALTER TASK OPS.APPLY_TASK SUSPEND;

-- Also stop the optional Lab 06 notebook consumer if it was created.

ALTER TASK IF EXISTS OPS.NOTEBOOK_APPLY_TASK SUSPEND;

ALTER TASK OPS.AUDIT_TASK SUSPEND;

ALTER PIPE BRONZE.ORDERS_PIPE SET PIPE_EXECUTION_PAUSED = TRUE;

ALTER DYNAMIC TABLE GOLD.ORDER_METRICS_DT SUSPEND;

ALTER DYNAMIC TABLE GOLD.ORDER_DETAIL_DT SUSPEND;

-- Run these only if the DMF branch was associated and not detached in lab 10.
-- ALTER TABLE OPS.DQ_DEMO DROP DATA METRIC FUNCTION
--     GOVERNANCE.NEGATIVE_AMOUNT_COUNT ON (AMOUNT);
-- ALTER TABLE OPS.DQ_DEMO UNSET DATA_METRIC_SCHEDULE;

SHOW DYNAMIC TABLES IN SCHEMA GOLD;

SHOW TASKS IN SCHEMA OPS;

SELECT SYSTEM$PIPE_STATUS('ADV_ORDERS.BRONZE.ORDERS_PIPE');

-- Wait for already-running executions before any future reset.

-- USE WAREHOUSE does not resume compute by itself. Suspend only if running.

EXECUTE IMMEDIATE $$
DECLARE
    warehouse_state STRING;
BEGIN
    SHOW WAREHOUSES LIKE 'ADV_WH';

    SELECT "state" INTO :warehouse_state
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    WHERE "name" = 'ADV_WH';

    IF (warehouse_state = 'STARTED') THEN
        ALTER WAREHOUSE ADV_WH SUSPEND;
    END IF;
END;
$$;

-- No DROP DATABASE or DROP ROLE: Day 3 reuses the same governance and Gold.

-- FINAL CHECK: all course tasks are suspended, the pipe is paused, and the
-- warehouse state below is SUSPENDED. Days 2-3 also require refreshes suspended.
-- Wait for already-running work to finish; SUSPEND prevents future task starts
-- but does not cancel a task that was already executing.
-- Do not run another data query after this check: AUTO_RESUME can wake ADV_WH.

SHOW WAREHOUSES LIKE 'ADV_WH';
