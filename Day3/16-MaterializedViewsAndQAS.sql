/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
C11 part 2 — Repeated aggregates and eligibility-driven acceleration
1) Build and query a supported aggregate materialized view
2) Check whether the optimizer rewrites the original query
3) Evaluate Query Acceleration eligibility before enabling a service
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 16 - Materialized aggregates and QAS estimate.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Create an aggregate materialization over one native table
-- ──────────────────────────────────────────────────────────────────────────────

-- Enterprise feature; direct table source and supported aggregate functions.

CREATE MATERIALIZED VIEW PERF.DAILY_ORDER_MV AS
SELECT ORDER_DATE, STATUS, COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) AS TOTAL_AMOUNT
FROM PERF.ORDERS_BASE
GROUP BY ORDER_DATE, STATUS;

SELECT SUM(ORDER_COUNT) AS ORDER_COUNT, SUM(TOTAL_AMOUNT) AS ORDER_AMOUNT
FROM PERF.DAILY_ORDER_MV
WHERE ORDER_DATE BETWEEN '2024-06-01'::DATE AND '2024-06-07'::DATE;

SET MV_QUERY_ID = LAST_QUERY_ID();

INSERT INTO PERF.MEASUREMENTS VALUES ('DATE_MV_DIRECT', $MV_QUERY_ID, CURRENT_TIMESTAMP());

-- CHECKPOINT: same count/amount as DATE_BASELINE.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Separate explicit MV reads from transparent optimizer rewrite
-- ──────────────────────────────────────────────────────────────────────────────

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) AS ORDER_AMOUNT
FROM PERF.ORDERS_BASE
WHERE ORDER_DATE BETWEEN '2024-06-01'::DATE AND '2024-06-07'::DATE;

SET REWRITE_QUERY_ID = LAST_QUERY_ID();

INSERT INTO PERF.MEASUREMENTS VALUES ('DATE_AFTER_MV', $REWRITE_QUERY_ID, CURRENT_TIMESTAMP());

EXPLAIN USING TEXT
SELECT COUNT(*), SUM(AMOUNT)
FROM PERF.ORDERS_BASE
WHERE ORDER_DATE BETWEEN '2024-06-01'::DATE AND '2024-06-07'::DATE;

-- Inspect the scan target. Optimizer rewrite is chosen by Snowflake, not promised.
-- Materialized maintenance and storage consume resources beyond the SELECT.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Evaluate QAS eligibility using a captured query ID
-- ──────────────────────────────────────────────────────────────────────────────

SET QAS_CANDIDATE = (
    SELECT QUERY_ID FROM PERF.MEASUREMENTS
    WHERE CASE_NAME = 'DATE_BASELINE' ORDER BY RECORDED_AT DESC LIMIT 1);

SELECT PARSE_JSON(SYSTEM$ESTIMATE_QUERY_ACCELERATION($QAS_CANDIDATE)) AS ESTIMATE;

-- Ineligible is a valid observation, especially at this scale.
-- The estimate is not a measured speedup. Enable only the separately rehearsed branch.

-- Optional-QAS.sql creates a separate bounded warehouse; it does not change ADV_WH.
-- Final shutdown suspends the lab materialized view so background maintenance stops.
