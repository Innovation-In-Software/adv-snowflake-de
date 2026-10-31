/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
1) Suspend tasks and pause ingestion
2) Check for in-flight work
3) Preserve the database for the next course day
----------------------------------------------------------------------------------*/

-- 99 | End-of-day stop: preserve data for Day 2
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
USE DATABASE ADV_ORDERS;

ALTER TASK OPS.APPLY_TASK SUSPEND;

-- Also stop the optional Lab 06 notebook consumer if it was created.

ALTER TASK IF EXISTS OPS.NOTEBOOK_APPLY_TASK SUSPEND;

ALTER TASK OPS.AUDIT_TASK SUSPEND;

ALTER PIPE BRONZE.ORDERS_PIPE SET PIPE_EXECUTION_PAUSED=TRUE;
-- Suspension does not cancel an already executing task. Inspect task history;
-- wait for in-flight work to finish before any reset.
SHOW TASKS IN SCHEMA OPS;

SELECT SYSTEM$PIPE_STATUS('ADV_ORDERS.BRONZE.ORDERS_PIPE');

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
-- If warehouse is already suspended, that statement can report that state.
-- No DROP DATABASE here. Day 2 uses the same Bronze/Silver/Gold objects.

-- FINAL CHECK: all course tasks are suspended, the pipe is paused, and the
-- warehouse state below is SUSPENDED. Days 2-3 also require refreshes suspended.
-- Wait for already-running work to finish; SUSPEND prevents future task starts
-- but does not cancel a task that was already executing.
-- Do not run another data query after this check: AUTO_RESUME can wake ADV_WH.

SHOW WAREHOUSES LIKE 'ADV_WH';
