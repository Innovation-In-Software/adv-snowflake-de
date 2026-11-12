/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
-- Part 1 — 50M rows: partition pruning, physical order and search optimization
1) Compare equivalent results on differently ordered 50M-row layouts
2) Separate physical pruning from cache and warehouse effects
3) Compare one-time ordering with a maintained clustering policy
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 15 - Physical ordering comparison.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';
ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Build equivalent ordered and keyed comparison tables
-- ──────────────────────────────────────────────────────────────────────────────

CREATE TABLE PERF.ORDERS_SORTED AS
SELECT * FROM PERF.ORDERS_BASE ORDER BY ORDER_DATE;

CREATE TABLE PERF.ORDERS_CLUSTERED CLUSTER BY (ORDER_DATE) AS
SELECT * FROM PERF.ORDERS_BASE;

-- CHECKPOINT: both tables contain the same 50000000 rows as ORDERS_BASE.
SELECT 'BASE' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM PERF.ORDERS_BASE
UNION ALL
SELECT 'ORDERED', COUNT(*) FROM PERF.ORDERS_SORTED
UNION ALL
SELECT 'CLUSTERED', COUNT(*) FROM PERF.ORDERS_CLUSTERED;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Compare cold-cache pruning for the same date-range query
-- ──────────────────────────────────────────────────────────────────────────────

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- Suspend and resume to clear the warehouse cache before this table's query.
USE ROLE ACCOUNTADMIN;
ALTER WAREHOUSE ADV_WH SUSPEND;
ALTER WAREHOUSE ADV_WH RESUME;
USE ROLE ADV_LAB;

EXPLAIN USING TEXT
SELECT COUNT(*), SUM(AMOUNT)
FROM PERF.ORDERS_SORTED
WHERE ORDER_DATE BETWEEN '2024-06-01'::DATE AND '2024-06-07'::DATE;

SELECT COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) AS ORDER_AMOUNT
FROM PERF.ORDERS_SORTED
WHERE ORDER_DATE BETWEEN '2024-06-01'::DATE AND '2024-06-07'::DATE;

-- CHECKPOINT (2026-11-09 rehearsal): 479452 rows, $124655461.53;
-- EXPLAIN 1/16 partitions assigned; query profile 1 partition scanned.
SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID(-1)));

-- Clear the warehouse cache again before the keyed-table comparison.
USE ROLE ACCOUNTADMIN;
ALTER WAREHOUSE ADV_WH SUSPEND;
ALTER WAREHOUSE ADV_WH RESUME;
USE ROLE ADV_LAB;

EXPLAIN USING TEXT
SELECT COUNT(*), SUM(AMOUNT)
FROM PERF.ORDERS_CLUSTERED
WHERE ORDER_DATE BETWEEN '2024-06-01'::DATE AND '2024-06-07'::DATE;

SELECT COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) AS ORDER_AMOUNT
FROM PERF.ORDERS_CLUSTERED
WHERE ORDER_DATE BETWEEN '2024-06-01'::DATE AND '2024-06-07'::DATE;

-- CHECKPOINT (2026-11-09 rehearsal): 479452 rows, $124655461.53;
-- EXPLAIN 1/16 partitions assigned; query profile 1 partition scanned.
SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID(-1)));

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Contrast one-time sorting with a maintained clustering policy
-- ──────────────────────────────────────────────────────────────────────────────

-- Both layouts pruned to 1 of 16 partitions in the measured date-range query.
-- ORDER BY physically sorts once at CTAS time. CLUSTER BY defines a maintained
-- clustering policy; suspend its serverless reclustering after this comparison.
USE ROLE ACCOUNTADMIN;
ALTER TABLE ADV_ORDERS.PERF.ORDERS_CLUSTERED SUSPEND RECLUSTER;
USE ROLE ADV_LAB;

-- Optional-SOS.sql contains the selective-lookup experiment.
-- Do not wait indefinitely for serverless build in core classroom time.
-- If prevalidated search access paths are unavailable, compare the diagnosis
-- and documented plan without claiming a measured SOS result.
