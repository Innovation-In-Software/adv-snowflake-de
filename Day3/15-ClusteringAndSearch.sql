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

CREATE OR REPLACE TABLE PERF.ORDERS_SORTED 
AS
SELECT * 
FROM PERF.ORDERS_BASE 
ORDER BY ORDER_DATE;

CREATE OR REPLACE TABLE PERF.ORDERS_CLUSTERED 
CLUSTER BY (ORDER_DATE) 
AS
SELECT * 
FROM PERF.ORDERS_BASE;

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

-- A temporary procedure belongs to this worksheet session; recreate it if you
-- open a new session. It runs with the caller's privileges: environment setup
-- grants ADV_LAB OPERATE on ADV_WH, so no role switch is needed.
-- Suspending and resuming clears the warehouse data cache. This is separate
-- from USE_CACHED_RESULT, which disables reuse of persisted query results.
-- Restarting affects other sessions and may incur warehouse startup charges.
-- In a shared account, use an isolated warehouse and adapt this procedure;
-- do not suspend a warehouse another user is working on.
CREATE OR REPLACE TEMPORARY PROCEDURE OPS.SP_RESTART_ADV_WH()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    ALTER WAREHOUSE ADV_WH SUSPEND;
    ALTER WAREHOUSE ADV_WH RESUME;
    RETURN 'ADV_WH suspended and resumed: ADV_WH cache cleared.';
END;
$$;

-- Restart before each comparison; resolve any error before measuring.
CALL OPS.SP_RESTART_ADV_WH();

EXPLAIN USING TEXT
SELECT COUNT(*), SUM(AMOUNT)
FROM PERF.ORDERS_SORTED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

SELECT COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) AS ORDER_AMOUNT
FROM PERF.ORDERS_SORTED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

-- CHECKPOINT (2026-11-09 rehearsal): 479,452 rows, $124,655,461.53;
-- EXPLAIN 1/16 partitions assigned; query profile 1 partition scanned.
SELECT * 
FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID(-1)));

-- Clear the warehouse cache again before the keyed-table comparison.
CALL OPS.SP_RESTART_ADV_WH();

EXPLAIN USING TEXT
SELECT COUNT(*), SUM(AMOUNT)
FROM PERF.ORDERS_CLUSTERED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

SELECT COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) AS ORDER_AMOUNT
FROM PERF.ORDERS_CLUSTERED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

-- CHECKPOINT (2026-11-09 rehearsal): 479,452 rows, $124,655,461.53;
-- EXPLAIN 1/16 partitions assigned; query profile 1 partition scanned.
SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID(-1)));

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Load more data and compare the layouts over time
-- ──────────────────────────────────────────────────────────────────────────────

-- Both layouts pruned to 1 of 16 partitions in the measured date-range query.
-- ORDER BY physically sorts once at CTAS time. CLUSTER BY defines a maintained
-- clustering policy. Automatic clustering remains enabled during the load
-- and measurements; it is asynchronous and incurs serverless charges.

-- Run this step once after Step 1; rerun Step 1 to reset before repeating it.
-- Insert the same deterministic 10 million rows into each table. Dates span
-- the original range rather than arriving in ORDER_DATE order. ORDERS_BASE
-- remains at 50 million rows for the other performance labs.
-- INSERT ALL sends every generated row to both targets in one statement.

INSERT ALL
    INTO PERF.ORDERS_SORTED
    INTO PERF.ORDERS_CLUSTERED
WITH NUMBERS AS
(
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 + 50000000 AS N
    FROM TABLE(GENERATOR(ROWCOUNT => 10000000))
)
SELECT N + 1 AS ORDER_ID,
       MOD(N * 7919, 100000) + 1 AS CUSTOMER_ID,
       DATEADD('day', MOD(N * 37, 730), '2024-01-01'::DATE) AS ORDER_DATE,
       IFF(MOD(N, 7) = 0, 'CANCELLED', 'PAID') AS STATUS,
       ((MOD(N * 97, 50000) + 1000) / 100)::NUMBER(12, 2) AS AMOUNT
FROM NUMBERS;

SELECT 'ORDERED' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM PERF.ORDERS_SORTED
UNION ALL
SELECT 'CLUSTERED', COUNT(*) FROM PERF.ORDERS_CLUSTERED;

-- CHECKPOINT: 60000000 rows in each table. If a load fails, do not repeat it
-- blindly: rebuild both comparison tables from Step 1 before retrying Step 3.

-- STEP 3a │ Measure both layouts after the load.
-- Record each EXPLAIN's partitions assigned/total and each query's ID and
-- profile partitions scanned. Compare with Step 2; do not assume degradation.
-- Automatic clustering may already have run on the clustered table; this is
-- not a controlled measurement of its state before maintenance.
-- Warehouse suspension affects all sessions using ADV_WH. In a shared account,
-- use an isolated warehouse instead; do not interrupt another user's work.

CALL OPS.SP_RESTART_ADV_WH();

EXPLAIN USING TEXT
SELECT COUNT(*), SUM(AMOUNT)
FROM PERF.ORDERS_SORTED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

SELECT COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) AS ORDER_AMOUNT
FROM PERF.ORDERS_SORTED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID(-1)));

CALL OPS.SP_RESTART_ADV_WH();

EXPLAIN USING TEXT
SELECT COUNT(*), SUM(AMOUNT)
FROM PERF.ORDERS_CLUSTERED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

SELECT COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) AS ORDER_AMOUNT
FROM PERF.ORDERS_CLUSTERED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID(-1)));

-- CHECKPOINT: both queries return 575342 rows and 149590962.53 USD. These
-- deterministic totals are calculated from the fixture, not a live rehearsal.
-- Partition counts are observations, not fixed acceptance values.

-- STEP 3b │ Observe automatic clustering, then compare again.
-- This service uses serverless compute and incurs charges. Its work is
-- asynchronous and Snowflake decides when reclustering is beneficial.
-- Wait at most five minutes, periodically rerunning the clustered EXPLAIN below.
-- Record whether pruning changes; no observed change within the wait is
-- inconclusive, not a failure. Never wait for a particular partition count.

EXPLAIN USING TEXT
SELECT COUNT(*), SUM(AMOUNT)
FROM PERF.ORDERS_CLUSTERED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

-- STOP/GO: after observing a change or reaching the five-minute limit,
-- continue to the final comparison. If a measurement fails or class stops
-- early, skip to the cleanup at the end of Step 3.

-- STEP 3c │ Compare the layouts again with Step 3a.
-- Use the same cold-cache procedure as above and record EXPLAIN, query IDs and
-- profile partitions scanned for both tables. Results must remain equal.
-- A CTAS rebuild can restore ordering to the sorted table, but it does not
-- maintain that order automatically after later loads.

CALL OPS.SP_RESTART_ADV_WH();

EXPLAIN USING TEXT
SELECT COUNT(*), SUM(AMOUNT) FROM PERF.ORDERS_SORTED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

SELECT COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) FROM PERF.ORDERS_SORTED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID(-1)));

CALL OPS.SP_RESTART_ADV_WH();

EXPLAIN USING TEXT
SELECT COUNT(*), SUM(AMOUNT) FROM PERF.ORDERS_CLUSTERED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

SELECT COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) FROM PERF.ORDERS_CLUSTERED
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID(-1)));

-- CHECKPOINT: both queries still return 575342 rows and 149590962.53 USD.
-- Compare actual partition counts with Step 3a and report the observed result.

-- STOP: suspend automatic reclustering even if no improvement was observed.
-- Suspending prevents future automatic reclustering; record any in-flight work.
USE ROLE ACCOUNTADMIN;
ALTER TABLE ADV_ORDERS.PERF.ORDERS_CLUSTERED SUSPEND RECLUSTER;
USE ROLE ADV_LAB;

SHOW TABLES LIKE 'ORDERS_CLUSTERED' IN SCHEMA PERF;
-- CHECKPOINT: automatic_clustering is OFF. If cleanup fails, resolve it before
-- leaving; the shutdown script also identifies this table.

-- Optional-SOS.sql contains the selective-lookup experiment.
-- Do not wait indefinitely for serverless build in core classroom time.
-- If prevalidated search access paths are unavailable, compare the diagnosis
-- and documented plan without claiming a measured SOS result.
