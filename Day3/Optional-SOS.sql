/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
-- Optional — selective search optimization
1) Copy sample orders into an independent table
2) Compare the same customer lookup before and after search optimization
3) Inspect pruning and remove the lab resources
----------------------------------------------------------------------------------*/

-- Search optimization requires Enterprise Edition and access to
-- SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.ORDERS. It uses serverless compute and
-- storage, which are billed separately from the dedicated warehouse.
-- The 150-million-row copy also incurs warehouse and storage charges.

USE ROLE ACCOUNTADMIN;

-- CREATE fails if this warehouse already exists. Stop and confirm ownership
-- before using or dropping it; it may belong to another workload.
CREATE WAREHOUSE ADV_SOS_WH
    WAREHOUSE_SIZE = 'XSMALL'
    ENABLE_QUERY_ACCELERATION = FALSE
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

GRANT USAGE, OPERATE ON WAREHOUSE ADV_SOS_WH TO ROLE ADV_LAB;

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_SOS_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA PERF;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3_SOS';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Copy sample data and measure a customer lookup
-- ──────────────────────────────────────────────────────────────────────────────

-- The sample table is read-only. This copy is ordered by order key, not
-- customer key; it has no automatic clustering. CREATE fails if it exists:
-- confirm ownership before using or dropping an existing table.
CREATE TABLE PERF.TPCH_ORDERS_SOS AS
SELECT O_ORDERKEY, O_CUSTKEY, O_ORDERDATE, O_TOTALPRICE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.ORDERS
ORDER BY O_ORDERKEY;

SHOW TABLES LIKE 'TPCH_ORDERS_SOS' IN SCHEMA PERF;
-- CHECKPOINT: 150,000,000 rows.

-- Clear warehouse cache after the copy. Execute individually: skip SUSPEND
-- if already SUSPENDED, and repeat SHOW until SUSPENDED before RESUME.
-- Restarting incurs a warehouse startup charge.
ALTER WAREHOUSE ADV_SOS_WH SUSPEND;
SHOW WAREHOUSES LIKE 'ADV_SOS_WH';
-- STOP: wait for SUSPENDED before resuming.
ALTER WAREHOUSE ADV_SOS_WH RESUME;

EXPLAIN
SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS TOTAL_PRICE
FROM PERF.TPCH_ORDERS_SOS
WHERE O_CUSTKEY = 5000000;

SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS TOTAL_PRICE
FROM PERF.TPCH_ORDERS_SOS
WHERE O_CUSTKEY = 5000000;

SET SOS_OFF_ID = LAST_QUERY_ID();

SELECT OPERATOR_TYPE, OPERATOR_STATISTICS
FROM TABLE(GET_QUERY_OPERATOR_STATS($SOS_OFF_ID));

-- CHECKPOINT: 14 orders, total price 1821437.53. Record TableScan partitions,
-- bytes, and percentage_scanned_from_cache; a cold scan should show 0.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Build the search access path and repeat
-- ──────────────────────────────────────────────────────────────────────────────

ALTER TABLE PERF.TPCH_ORDERS_SOS ADD SEARCH OPTIMIZATION ON EQUALITY(O_CUSTKEY);

SHOW TABLES LIKE 'TPCH_ORDERS_SOS' IN SCHEMA PERF;

SHOW TABLES LIKE 'TPCH_ORDERS_SOS' IN SCHEMA PERF
->>
SELECT "name", "rows", "search_optimization", "search_optimization_progress", "bytes", "search_optimization_bytes"
FROM $1;
-- STOP: repeat SHOW until search_optimization_progress is 100. Initialization
-- runs in the background and can take several minutes; if it does not finish,
-- investigate or proceed to cleanup. Do not compare before it is ready.

-- Clear warehouse cache again for a comparable scan.
ALTER WAREHOUSE ADV_SOS_WH SUSPEND;
SHOW WAREHOUSES LIKE 'ADV_SOS_WH';
-- STOP: wait for SUSPENDED before resuming.
ALTER WAREHOUSE ADV_SOS_WH RESUME;

EXPLAIN
SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS TOTAL_PRICE
FROM PERF.TPCH_ORDERS_SOS
WHERE O_CUSTKEY = 5000000;

SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS TOTAL_PRICE
FROM PERF.TPCH_ORDERS_SOS
WHERE O_CUSTKEY = 5000000;

SET SOS_ON_ID = LAST_QUERY_ID();

SELECT OPERATOR_TYPE, OPERATOR_STATISTICS
FROM TABLE(GET_QUERY_OPERATOR_STATS($SOS_ON_ID));

-- CHECKPOINT: the same 14 orders and total. Look for Search Optimization
-- Access and partitions_pruned_by_search_optimization in the operator stats;
-- compare partitions and cache percentages to Step 1. In one QA run the
-- scan changed from 40/40 partitions to 12/40, with 28 pruned by SOS.
-- The optimizer can choose another plan; neither SOS use nor a speedup is
-- guaranteed. EXPLAIN estimates and actual operator statistics can differ.

SELECT QUERY_ID, TOTAL_ELAPSED_TIME, EXECUTION_TIME, BYTES_SCANNED
FROM TABLE(ADV_ORDERS.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 100))
WHERE QUERY_ID IN ($SOS_OFF_ID, $SOS_ON_ID);

SELECT (MAX(TOTAL_ELAPSED_TIME)/MIN(TOTAL_ELAPSED_TIME))::number(38,1)  elapsed_time_factor, 
       (MAX(EXECUTION_TIME)/MIN(EXECUTION_TIME))::number(38,1)          execution_time_factor,
       (MAX(BYTES_SCANNED)/MIN(BYTES_SCANNED))::number(38,1)            bytes_scanned_factor
FROM TABLE(ADV_ORDERS.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 100))
WHERE QUERY_ID IN ($SOS_OFF_ID, $SOS_ON_ID);

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Cleanup
-- ──────────────────────────────────────────────────────────────────────────────

-- Run cleanup even if stopping early, but only for resources created by this
-- lab. Dropping the table also removes its search optimization and stops
-- maintenance; retained Time Travel data can still incur storage charges.
DROP TABLE IF EXISTS PERF.TPCH_ORDERS_SOS;
SHOW TABLES LIKE 'TPCH_ORDERS_SOS' IN SCHEMA PERF;
-- CHECKPOINT: no row.

USE WAREHOUSE ADV_WH;
USE ROLE ACCOUNTADMIN;
DROP WAREHOUSE IF EXISTS ADV_SOS_WH;
SHOW WAREHOUSES LIKE 'ADV_SOS_WH';
-- CHECKPOINT: no row.
USE ROLE ADV_LAB;
