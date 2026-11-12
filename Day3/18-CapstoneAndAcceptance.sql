/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
Course capstone — defend a complete operational design
1) Reconcile the shared order project under engineer and consumer roles
2) Summarize performance evidence without unsupported speedup claims
3) Explain governance, freshness and recovery tradeoffs
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 18 - Capstone and shutdown.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3';

-- Day 2 shutdown suspends Gold. Restore it for the capstone.
SET GOLD_PREFLIGHT_STARTED = CURRENT_TIMESTAMP();

ALTER DYNAMIC TABLE GOLD.ORDER_DETAIL_DT RESUME;
ALTER DYNAMIC TABLE GOLD.ORDER_METRICS_DT RESUME;
ALTER DYNAMIC TABLE GOLD.ORDER_DETAIL_DT REFRESH;
ALTER DYNAMIC TABLE GOLD.ORDER_METRICS_DT REFRESH;

-- Refreshes are asynchronous. Repeat the SHOW and freshness check in Step 1
-- until both tables pass; do not treat the refresh request alone as evidence.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Verify the shared business state
-- ──────────────────────────────────────────────────────────────────────────────

SELECT 'CURRENT_ORDERS' AS CHECK_NAME, IFF(COUNT(*) = 3, 'PASS', 'FAIL') AS RESULT FROM SILVER.ORDERS_CURRENT
UNION ALL
SELECT 'ACTIVE_VALUE', IFF(SUM(IFF(STATUS <> 'CANCELLED', AMOUNT, 0)) = 165, 'PASS', 'FAIL') FROM SILVER.ORDERS_CURRENT
UNION ALL
SELECT 'REJECT_EVIDENCE', IFF(COUNT(*) = 1, 'PASS', 'FAIL') FROM SILVER.VW_REJECTED_EVENTS
UNION ALL
SELECT 'STREAM_DRAINED', IFF(COUNT(*) = 0, 'PASS', 'FAIL') FROM BRONZE.EVENTS_STREAM;

-- CHECKPOINT: all PASS.

SHOW DYNAMIC TABLES IN SCHEMA GOLD;

SELECT "name" AS DYNAMIC_TABLE, "scheduling_state" AS SCHEDULING_STATE, "data_timestamp" AS DATA_TIMESTAMP,
       $GOLD_PREFLIGHT_STARTED AS PREFLIGHT_STARTED,
       IFF("scheduling_state" = 'ACTIVE' AND "data_timestamp"::DATE = CURRENT_DATE()
           AND "data_timestamp" >= $GOLD_PREFLIGHT_STARTED, 'PASS', 'FAIL') AS RESULT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "name" IN ('ORDER_DETAIL_DT', 'ORDER_METRICS_DT')
ORDER BY "name";

-- CHECKPOINT: both ORDER_DETAIL_DT and ORDER_METRICS_DT appear, show ACTIVE and
-- PASS, and have a data_timestamp today (UTC) at or after the preflight began.
-- If either is missing or fails, wait and repeat SHOW and this check. Investigate
-- a suspended table or a refresh that does not complete before proceeding.

SELECT * FROM GOLD.ORDER_METRICS_DT;

SELECT * FROM PERF.MEASUREMENTS ORDER BY RECORDED_AT;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Prove the consumer boundary still holds
-- ──────────────────────────────────────────────────────────────────────────────

USE ROLE ADV_ANALYST_US;
USE SECONDARY ROLES NONE;

SELECT ORDER_ID, REGION, EMAIL FROM CONSUMER.VW_ORDERS ORDER BY ORDER_ID;

-- CHECKPOINT: o1/o3, US, masked emails.

USE ROLE ADV_ANALYST_EU;
USE SECONDARY ROLES NONE;

SELECT ORDER_ID, REGION, EMAIL FROM CONSUMER.VW_ORDERS;

-- CHECKPOINT: o2, EU, masked.

USE ROLE ADV_LAB;
USE SECONDARY ROLES NONE;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Explain the design with captured evidence
-- ──────────────────────────────────────────────────────────────────────────────

-- Instructor asks; everyone responds using their own query IDs and outputs:
-- 1. Why do file replay and business event replay require different controls?
-- 2. Which transaction boundary prevents stream loss on a failed transformation?
-- 3. How do you distinguish current order value from event sums or revenue?
-- 4. What is the evidence for the last successful Gold refresh?
-- 5. Why is app owner identity different from a viewer's preferred role?
-- 6. Which query merits pruning, SOS, MV, QAS, sizing, or no persistent service?
-- 7. Which measurements would you require before promising a performance benefit?
-- 8. What remains unavailable in another region after an UNDROP?
-- Optional modern-ecosystem/Cortex discussion stays separate from these assertions.
