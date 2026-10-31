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

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Verify the shared business state
-- ──────────────────────────────────────────────────────────────────────────────

SELECT 'CURRENT_ORDERS' AS CHECK_NAME, IFF(COUNT(*) = 3, 'PASS', 'FAIL') AS RESULT FROM SILVER.ORDERS_CURRENT
UNION ALL
SELECT 'ACTIVE_VALUE', IFF(SUM(IFF(STATUS <> 'CANCELLED', AMOUNT, 0)) = 165, 'PASS', 'FAIL') FROM SILVER.ORDERS_CURRENT
UNION ALL
SELECT 'REJECT_EVIDENCE', IFF(COUNT(*) = 1, 'PASS', 'FAIL') FROM SILVER.REJECTED_EVENTS
UNION ALL
SELECT 'STREAM_DRAINED', IFF(COUNT(*) = 0, 'PASS', 'FAIL') FROM BRONZE.EVENTS_STREAM;

-- CHECKPOINT: all PASS. Dynamic Gold was restored before Day 2 shutdown.

SELECT * FROM GOLD.ORDER_METRICS_DT;

SELECT * FROM PERF.MEASUREMENTS ORDER BY RECORDED_AT;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Prove the consumer boundary still holds
-- ──────────────────────────────────────────────────────────────────────────────

USE ROLE ADV_ANALYST_US;
USE SECONDARY ROLES NONE;

SELECT ORDER_ID, REGION, EMAIL FROM CONSUMER.ORDERS ORDER BY ORDER_ID;

-- CHECKPOINT: o1/o3, US, masked emails.

USE ROLE ADV_ANALYST_EU;
USE SECONDARY ROLES NONE;

SELECT ORDER_ID, REGION, EMAIL FROM CONSUMER.ORDERS;

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
