/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
C11 part 1 — Pruning, physical order and optional search optimization
1) Compare equivalent results on differently ordered layouts
2) Separate physical pruning from cache and warehouse effects
3) Evaluate search optimization for a selective lookup
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 15 - Physical ordering comparison.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Create a physically ordered comparison table
-- ──────────────────────────────────────────────────────────────────────────────

CREATE TABLE PERF.ORDERS_SORTED AS
SELECT * FROM PERF.ORDERS_BASE ORDER BY ORDER_DATE;

-- Sorted CTAS isolates physical ordering. It is not proof of the long-term
-- benefit or cost of automatic reclustering under an evolving workload.

SELECT SYSTEM$CLUSTERING_INFORMATION('ADV_ORDERS.PERF.ORDERS_BASE', '(ORDER_DATE)');

SELECT SYSTEM$CLUSTERING_INFORMATION('ADV_ORDERS.PERF.ORDERS_SORTED', '(ORDER_DATE)');

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Run the same query and compare result values and scan work
-- ──────────────────────────────────────────────────────────────────────────────

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) AS ORDER_AMOUNT
FROM PERF.ORDERS_SORTED
WHERE ORDER_DATE BETWEEN '2024-06-01'::DATE AND '2024-06-07'::DATE;

SET SORTED_QUERY_ID = LAST_QUERY_ID();

INSERT INTO PERF.MEASUREMENTS VALUES ('DATE_SORTED', $SORTED_QUERY_ID, CURRENT_TIMESTAMP());

SELECT ORDER_DATE, COUNT(*) AS ROW_COUNT, SUM(AMOUNT) AS TOTAL FROM PERF.ORDERS_BASE GROUP BY ORDER_DATE
MINUS
SELECT ORDER_DATE, COUNT(*), SUM(AMOUNT) FROM PERF.ORDERS_SORTED GROUP BY ORDER_DATE;

-- CHECKPOINT: empty difference. Also compare total row counts; the generated
-- sorted table was derived from the exact baseline table.

SELECT M.CASE_NAME, Q.QUERY_ID,
       Q.BYTES_SCANNED, Q.EXECUTION_TIME, Q.TOTAL_ELAPSED_TIME
FROM PERF.MEASUREMENTS M
JOIN TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(RESULT_LIMIT => 1000)) Q
    ON M.QUERY_ID = Q.QUERY_ID
WHERE M.CASE_NAME IN ('DATE_BASELINE', 'DATE_SORTED');

-- Partition and spill metrics are in Query Profile / operator statistics,
-- not the Information Schema query-history columns.

SET DATE_BASELINE_ID = (SELECT QUERY_ID FROM PERF.MEASUREMENTS
    WHERE CASE_NAME = 'DATE_BASELINE' ORDER BY RECORDED_AT DESC LIMIT 1);

SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS($DATE_BASELINE_ID));

SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS($SORTED_QUERY_ID));

-- Repeat both queries three times with the same warehouse. Record warm/cold
-- conditions explicitly. Equal elapsed times do not negate measured scan savings.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Discuss a clustering key and isolate the optional SOS branch
-- ──────────────────────────────────────────────────────────────────────────────

-- Optional maintenance experiment, only after cost/edition rehearsal:
-- ALTER TABLE PERF.ORDERS_SORTED CLUSTER BY (ORDER_DATE);
-- ALTER TABLE PERF.ORDERS_SORTED SUSPEND RECLUSTER;
-- A key persists a maintenance policy; sorted CTAS alone does not.

-- Optional-SOS.sql contains the exact selective-lookup experiment.
-- Do not wait indefinitely for serverless build in core classroom time.
-- If prevalidated search access paths are unavailable, compare the diagnosis
-- and documented plan without claiming a measured SOS result.
