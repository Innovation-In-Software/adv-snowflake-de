/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
C10 — Diagnose before choosing an optimization
1) Read EXPLAIN, Query Profile and immediate query history
2) Capture query IDs and distinguish elapsed time components
3) Choose a hypothesis based on selectivity and physical work
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 14 - Measure before tuning.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Predict the work from a plan
-- ──────────────────────────────────────────────────────────────────────────────

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

EXPLAIN USING TEXT
SELECT COUNT(*), SUM(AMOUNT)
FROM PERF.ORDERS_BASE
WHERE ORDER_DATE BETWEEN '2024-06-01'::DATE AND '2024-06-07'::DATE;

-- EXPLAIN is a plan prediction; it is not an execution measurement.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Execute the baseline and record its identity immediately
-- ──────────────────────────────────────────────────────────────────────────────

SELECT COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) AS ORDER_AMOUNT
FROM PERF.ORDERS_BASE
WHERE ORDER_DATE BETWEEN '2024-06-01'::DATE AND '2024-06-07'::DATE;

SET BASELINE_QUERY_ID = LAST_QUERY_ID();

INSERT INTO PERF.MEASUREMENTS VALUES
    ('DATE_BASELINE', $BASELINE_QUERY_ID, CURRENT_TIMESTAMP());

SELECT QUERY_ID, EXECUTION_TIME, COMPILATION_TIME, TOTAL_ELAPSED_TIME,
       BYTES_SCANNED,
       QUEUED_OVERLOAD_TIME
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 100))
WHERE QUERY_ID = $BASELINE_QUERY_ID;

SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS($BASELINE_QUERY_ID));

-- In Snowsight open the captured query's profile. Locate TableScan, filter,
-- aggregation, scanned partitions and cache indicators. Save an observation.
-- An operator-stat privilege or unsupported-query error is recorded separately;
-- the query ID and profile UI remain the primary evidence.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Compare a point lookup and a join workload
-- ──────────────────────────────────────────────────────────────────────────────

SELECT ORDER_ID, ORDER_DATE, AMOUNT FROM PERF.ORDERS_BASE WHERE CUSTOMER_ID = 42 ORDER BY ORDER_ID;

SET LOOKUP_QUERY_ID = LAST_QUERY_ID();

INSERT INTO PERF.MEASUREMENTS VALUES ('POINT_BASELINE', $LOOKUP_QUERY_ID, CURRENT_TIMESTAMP());

-- CHECKPOINT: ten matching rows. This predicate differs from the date-range query.

SELECT C.REGION, SUM(O.AMOUNT) AS ACTIVE_AMOUNT
FROM PERF.ORDERS_BASE O
JOIN PERF.CUSTOMERS C ON O.CUSTOMER_ID = C.CUSTOMER_ID
WHERE O.STATUS = 'PAID'
GROUP BY C.REGION;

SET JOIN_QUERY_ID = LAST_QUERY_ID();

INSERT INTO PERF.MEASUREMENTS VALUES ('JOIN_BASELINE', $JOIN_QUERY_ID, CURRENT_TIMESTAMP());

SELECT * FROM PERF.MEASUREMENTS ORDER BY RECORDED_AT;

-- Diagnosis worksheet: predicate selectivity, partitions scanned, dominant
-- operator, spill, queueing, cache state, and proposed next experiment.
-- A large scan suggests layout/pruning; sparse equality suggests SOS; recurring
-- aggregates suggest MV; queueing suggests concurrency rather than a single-query fix.
