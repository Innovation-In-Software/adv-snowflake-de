/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
Day 2 preflight — verify the shared handoff
1) Confirm environment and the Day 1 business state
2) Create supporting schemas without resetting the pipeline
3) Record account capabilities for governed Gold
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 07 - Verify the handoff.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY2';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Resume compute and inspect the Day 1 state
-- ──────────────────────────────────────────────────────────────────────────────

ALTER WAREHOUSE ADV_WH RESUME IF SUSPENDED;

SELECT CURRENT_ACCOUNT(), CURRENT_REGION(), CURRENT_ROLE(), CURRENT_VERSION();

SELECT * FROM SILVER.ORDERS_CURRENT ORDER BY ORDER_ID;

SELECT * FROM GOLD.ORDER_METRICS;

SELECT COUNT(*) AS PENDING_ROWS FROM BRONZE.EVENTS_STREAM;

-- CHECKPOINT: 3 orders; active 2 / USD 165; no pending stream rows.
-- Cancellations remain in Silver. Stop and repair a mismatch before Day 2.

CREATE SCHEMA IF NOT EXISTS GOVERNANCE;

CREATE SCHEMA IF NOT EXISTS CONSUMER;

-- No DROP/CREATE of Bronze, streams or Silver is permitted as a handoff repair.

SHOW PROCEDURES LIKE 'APPLY_EVENTS_SNOWPARK' IN SCHEMA SILVER;

SHOW TASKS IN SCHEMA OPS;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Confirm the class feature profile
-- ──────────────────────────────────────────────────────────────────────────────

-- Instructor and students use the same edition/cloud/region. Dynamic Tables,
-- policy features and DMFs have separate capability and privilege requirements.
-- Edition is verified by the administrator in the account configuration.
-- Enterprise policy/DMF branches must be prevalidated before live class.
-- Root task remains suspended throughout Day 2; we use deliberate manual runs.

ALTER TASK OPS.APPLY_TASK SUSPEND;

ALTER TASK OPS.AUDIT_TASK SUSPEND;

SELECT 'DAY2_BASELINE' AS CHECKPOINT, COUNT(*) AS CURRENT_ORDERS,
       SUM(IFF(STATUS <> 'CANCELLED', AMOUNT, 0)) AS ACTIVE_AMOUNT_USD
FROM SILVER.ORDERS_CURRENT;
