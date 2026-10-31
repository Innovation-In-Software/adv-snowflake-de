/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
Optional C11 branch — selective search optimization
1) Build a separate search-optimized table for equality predicates
2) Observe serverless construction readiness
3) Measure the same point lookup and stop maintenance
----------------------------------------------------------------------------------*/

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Create a separate optional table
-- ──────────────────────────────────────────────────────────────────────────────

-- Enterprise feature and serverless cost. Rehearse this branch before class.

CREATE TABLE PERF.ORDERS_SEARCH CLONE PERF.ORDERS_BASE;

ALTER TABLE PERF.ORDERS_SEARCH ADD SEARCH OPTIMIZATION ON EQUALITY(CUSTOMER_ID);

SHOW TABLES LIKE 'ORDERS_SEARCH' IN SCHEMA PERF;

-- Inspect search_optimization_progress; proceed only when the access path is ready.
-- The optimizer can choose another plan; enabling SOS does not guarantee use.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Measure a selective equality lookup after readiness
-- ──────────────────────────────────────────────────────────────────────────────

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT ORDER_ID, ORDER_DATE, AMOUNT FROM PERF.ORDERS_SEARCH WHERE CUSTOMER_ID = 42 ORDER BY ORDER_ID;

SET SEARCH_QUERY_ID = LAST_QUERY_ID();

INSERT INTO PERF.MEASUREMENTS VALUES ('POINT_SOS', $SEARCH_QUERY_ID, CURRENT_TIMESTAMP());

-- CHECKPOINT: the same ten rows as POINT_BASELINE. Inspect profile for access path.

SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS($SEARCH_QUERY_ID));

ALTER TABLE PERF.ORDERS_SEARCH DROP SEARCH OPTIMIZATION;

-- Remove only the lab's search service; do not modify production objects.
