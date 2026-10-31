/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
C11 operations — Cache, sizing, concurrency and recovery
1) Distinguish persisted results, warehouse cache and warehouse sizing
2) Observe independent concurrent sessions without a hidden load generator
3) Recover a training object and explain the limits of local recovery
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 17 - Cache, compute and local recovery.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3';

-- SETUP: prepare the disposable recovery target before the experiments.
-- The clone starts with the baseline data; later DROP/UNDROP tests this copy only.

CREATE TABLE PERF.RECOVERY_COPY CLONE PERF.ORDERS_BASE;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Control persisted-result reuse explicitly
-- ──────────────────────────────────────────────────────────────────────────────

ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT SUM(AMOUNT) AS TOTAL_AMOUNT FROM PERF.ORDERS_BASE;

SET CACHE_FIRST_ID = LAST_QUERY_ID();

SELECT SUM(AMOUNT) AS TOTAL_AMOUNT FROM PERF.ORDERS_BASE;

SET CACHE_REPEAT_ID = LAST_QUERY_ID();

INSERT INTO PERF.MEASUREMENTS VALUES
    ('CACHE_FIRST', $CACHE_FIRST_ID, CURRENT_TIMESTAMP()),
    ('CACHE_REPEAT', $CACHE_REPEAT_ID, CURRENT_TIMESTAMP());

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- Inspect profile/history; matching text is only one of the reuse conditions.
-- Warehouse-local data cache is separate and can still influence this next query.

SELECT SUM(AMOUNT) AS TOTAL_AMOUNT FROM PERF.ORDERS_BASE;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Measure sizing in a separate lab warehouse
-- ──────────────────────────────────────────────────────────────────────────────

USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE ADV_TUNE_WH
    WAREHOUSE_SIZE = 'XSMALL'
    ENABLE_QUERY_ACCELERATION = FALSE
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

GRANT USAGE, OPERATE, MODIFY ON WAREHOUSE ADV_TUNE_WH TO ROLE ADV_LAB;

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_TUNE_WH;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT C.REGION, SUM(O.AMOUNT)
FROM PERF.ORDERS_BASE O JOIN PERF.CUSTOMERS C ON O.CUSTOMER_ID = C.CUSTOMER_ID
GROUP BY C.REGION;

SET XS_QUERY_ID = LAST_QUERY_ID();

ALTER WAREHOUSE ADV_TUNE_WH SET WAREHOUSE_SIZE = 'SMALL';

SELECT C.REGION, SUM(O.AMOUNT)
FROM PERF.ORDERS_BASE O JOIN PERF.CUSTOMERS C ON O.CUSTOMER_ID = C.CUSTOMER_ID
GROUP BY C.REGION;

SET SMALL_QUERY_ID = LAST_QUERY_ID();

INSERT INTO PERF.MEASUREMENTS VALUES
    ('SIZE_XS', $XS_QUERY_ID, CURRENT_TIMESTAMP()),
    ('SIZE_SMALL', $SMALL_QUERY_ID, CURRENT_TIMESTAMP());

ALTER WAREHOUSE ADV_TUNE_WH SET WAREHOUSE_SIZE = 'XSMALL';

ALTER WAREHOUSE ADV_TUNE_WH SUSPEND;

USE WAREHOUSE ADV_WH;

-- Repeat with controlled warm/cold conditions. Runtime plus credit rate determines
-- cost per completed workload; a larger warehouse is not automatically cheaper.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Use an explicit two-session concurrency experiment
-- ──────────────────────────────────────────────────────────────────────────────

-- Open worksheet A and B. In BOTH: select ADV_LAB / ADV_TUNE_WH and disable
-- persisted-result reuse. Run the same join above simultaneously after a countdown.
-- Save both query IDs. Inspect queued_overload_time versus execution_time.
-- A small fixture may show no queueing: report that result, do not invent pressure.
-- Scale-out addresses concurrency; scale-up changes single-cluster capacity.
-- Multi-cluster configuration is an entitlement-dependent extension, not required.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 4 │ Recover a disposable table without touching the business pipeline
-- ──────────────────────────────────────────────────────────────────────────────

SELECT COUNT(*) FROM PERF.RECOVERY_COPY; -- 1000000

DROP TABLE PERF.RECOVERY_COPY;

UNDROP TABLE PERF.RECOVERY_COPY;

SELECT COUNT(*) FROM PERF.RECOVERY_COPY; -- 1000000 restored

-- Clone and Time Travel are local recovery tools. They do not prove another
-- region/account is ready, nor replace tested replication, RPO/RTO and failover.
-- Optional practice: recover a controlled UPDATE with a recorded statement ID.
