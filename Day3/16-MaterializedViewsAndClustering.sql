/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
-- Part 2 — Materialized views and alternative clustering
1) One physical layout is not optimal for every query
2) A materialized view maintains another representation for a different access pattern
3) Separate direct MV performance from the optimizer's rewrite decision
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 16 - Alternative clustering key.
-- Materialized views require Snowflake Enterprise Edition. This lab also
-- requires SELECT access to SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.ORDERS.
-- This independent experiment creates a separate 150M-row copy and warehouse;
-- Lab 15's tables and the main pipeline warehouse remain unchanged.
-- Create a dedicated warehouse so cache resets do not interrupt pipeline work.
-- If LAB16_WH already exists, verify it is dedicated to this lab and has
-- these settings and grants; skip CREATE rather than replacing it.
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE WAREHOUSE LAB16_WH
    WAREHOUSE_SIZE = 'XSMALL'
    ENABLE_QUERY_ACCELERATION = FALSE
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

GRANT USAGE, OPERATE ON WAREHOUSE LAB16_WH TO ROLE ADV_LAB;

USE ROLE ADV_LAB;
USE WAREHOUSE LAB16_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';
ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3';
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Build a date-organized copy and measure date pruning
-- ──────────────────────────────────────────────────────────────────────────────

-- STOP/GO: confirm the shared sample data is accessible before building.
-- If it is unavailable, ask the instructor; do not silently substitute data.

SELECT COUNT(*) AS ROW_COUNT 
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.ORDERS;
-- CHECKPOINT: 150,000,000 rows.

-- The sample database is read-only. Copy all columns into our own schema,
-- physically order by date, and define the table's date clustering key.
-- Replacing this table invalidates any existing MV based on its old version;
-- Step 3 replaces this lab's MV. This copy adds storage and build cost.

CREATE OR REPLACE TABLE PERF.TPCH_ORDERS_BY_DATE
CLUSTER BY (O_ORDERDATE) AS
SELECT O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE,
       O_ORDERPRIORITY, O_CLERK, O_SHIPPRIORITY, O_COMMENT
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.ORDERS
ORDER BY O_ORDERDATE;

-- Stop base maintenance during the experiment; the date key remains defined.
ALTER TABLE PERF.TPCH_ORDERS_BY_DATE SUSPEND RECLUSTER;

SELECT COUNT(*) AS ROW_COUNT        -- CHECKPOINT: 150000000 rows.
FROM PERF.TPCH_ORDERS_BY_DATE;


-- Disable persisted result reuse above. For cold-cache measurements, the
-- warehouse must fully suspend before it is resumed. Each restart incurs
-- startup charges and affects any other session using LAB16_WH.
-- The permanent procedure runs from a serverless task, not LAB16_WH itself.
-- It cancels ALL queries on LAB16_WH, suspends it, waits 10 seconds by
-- default, then resumes it. This simple lab assumes LAB16_WH is running.
-- The wait is not a guarantee of full suspension; check the query profile.
-- Pass another number of seconds in the task's CALL to change the wait.
-- The task has no schedule and only runs when explicitly executed.
-- ADV_LAB needs OPERATE on LAB16_WH and EXECUTE MANAGED TASK on the account.
-- The task incurs serverless charges; recreating it can cancel an active run.


CREATE OR REPLACE PROCEDURE OPS.SP_RESTART_LAB16_WH(WAIT_SECONDS INTEGER DEFAULT 10)
RETURNS STRING
EXECUTE AS CALLER
AS
$$
BEGIN
    ALTER WAREHOUSE LAB16_WH ABORT ALL QUERIES;
    ALTER WAREHOUSE LAB16_WH SUSPEND;
    CALL SYSTEM$WAIT(:WAIT_SECONDS);
    ALTER WAREHOUSE LAB16_WH RESUME IF SUSPENDED;
    RETURN 'LAB16_WH restarted: cache cleared,';
END;
$$;

CREATE OR REPLACE TASK OPS.TASK_RESTART_LAB16_WH
    USER_TASK_TIMEOUT_MS = 90000
    SERVERLESS_TASK_MAX_STATEMENT_SIZE = 'XSMALL'
AS CALL OPS.SP_RESTART_LAB16_WH();

-- Each EXECUTE TASK below is asynchronous. After each call, STOP: in
-- Snowsight under Transformation > Tasks, open TASK_RESTART_LAB16_WH and
-- wait for THIS run to show SUCCEEDED. If it fails or times out, inspect
-- its run details and resolve the error; do not run the measurement.
-- Do not run AWAIT from LAB16_WH: ABORT ALL QUERIES cancels that statement.
-- Do not query task history from LAB16_WH while the task is running: that
-- can resume it early. Check each profile's cache percentage; if nonzero,
-- repeat the restart and measurement.

EXPLAIN
SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS ORDER_AMOUNT
FROM PERF.TPCH_ORDERS_BY_DATE
WHERE O_ORDERDATE BETWEEN DATE'1995-03-01' AND DATE'1995-03-07';

EXPLAIN
SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS ORDER_AMOUNT
FROM PERF.TPCH_ORDERS_BY_DATE
WHERE O_ORDERDATE BETWEEN DATE'1995-03-01' AND DATE'1995-03-07'
->>
SELECT "partitionsTotal", "partitionsAssigned"
FROM $1
WHERE "operation" = 'GlobalStats';

EXECUTE TASK OPS.TASK_RESTART_LAB16_WH;
-- STOP: wait for this task run to SUCCEED in Snowsight before continuing.

SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS ORDER_AMOUNT
FROM PERF.TPCH_ORDERS_BY_DATE
WHERE O_ORDERDATE BETWEEN DATE'1995-03-01' AND DATE'1995-03-07';

SET DATE_QUERY_ID = LAST_QUERY_ID();

SELECT * 
FROM TABLE(GET_QUERY_OPERATOR_STATS($DATE_QUERY_ID));

-- CHECKPOINT (QA rehearsal, X-Small, cold): 435659 orders, 65801651231.17;
-- EXPLAIN assigned 1/135; profile scanned 1/135 and 1900624 bytes.
-- Partition counts, bytes and timings are observations, not guarantees.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Measure customer lookup before creating the MV
-- ──────────────────────────────────────────────────────────────────────────────

-- This customer's orders span dates. Date ordering is not necessarily useful
-- for a customer predicate. Capture the scan target and query ID.
EXPLAIN
SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS ORDER_AMOUNT
FROM PERF.TPCH_ORDERS_BY_DATE 
WHERE O_CUSTKEY = 7918018;

EXPLAIN
SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS ORDER_AMOUNT
FROM PERF.TPCH_ORDERS_BY_DATE 
WHERE O_CUSTKEY = 7918018
->>
SELECT "partitionsTotal", "partitionsAssigned"
FROM $1
WHERE "operation" = 'GlobalStats';

EXECUTE TASK OPS.TASK_RESTART_LAB16_WH;
-- STOP: wait for this task run to SUCCEED in Snowsight before continuing.

SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS ORDER_AMOUNT
FROM PERF.TPCH_ORDERS_BY_DATE 
WHERE O_CUSTKEY = 7918018;

SET CUSTOMER_BASE_QUERY_ID = LAST_QUERY_ID();

SELECT * 
FROM TABLE(GET_QUERY_OPERATOR_STATS($CUSTOMER_BASE_QUERY_ID));

-- CHECKPOINT (QA rehearsal, X-Small, cold): 18 orders, 2467651.95;
-- base TableScan assigned and scanned 135/135, 505564016 bytes.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Create a customer-clustered materialized view
-- ──────────────────────────────────────────────────────────────────────────────

-- This projection preserves individual orders in a separate physical layout.
-- It covers the customer aggregate but deliberately excludes four base columns.
CREATE OR REPLACE MATERIALIZED VIEW PERF.MVW_BY_CUSTOMER
CLUSTER BY (O_CUSTKEY) AS
SELECT O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE
FROM PERF.TPCH_ORDERS_BY_DATE;

SET MV_BUILD_QUERY_ID = LAST_QUERY_ID();

SHOW MATERIALIZED VIEWS LIKE 'MVW_BY_CUSTOMER' IN SCHEMA PERF;

SELECT COUNT(*) AS ROW_COUNT 
FROM PERF.MVW_BY_CUSTOMER;

SELECT $MV_BUILD_QUERY_ID AS MV_BUILD_QUERY_ID;

-- CHECKPOINT (QA rehearsal): 150,000,000 rows; 1,762,460,160 bytes; invalid=false,
-- clustered by O_CUSTKEY; CREATE client elapsed 35.437 seconds. Check Query
-- History for build time. Storage, timing and physical layout can vary.

-- Initial creation materializes the MV; clustering can continue asynchronously.
-- Re-run EXPLAIN and look for the MV scan and pruning before Step 4. In the
-- QA run it assigned 1/56 partitions immediately and again 10 seconds later.
-- STOP/GO: if pruning does not appear during class, record that and continue
-- without claiming an improvement; if stopping early, run Step 6 cleanup.

EXPLAIN
SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS ORDER_AMOUNT
FROM PERF.MVW_BY_CUSTOMER 
WHERE O_CUSTKEY = 7918018;

EXPLAIN
SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS ORDER_AMOUNT
FROM PERF.MVW_BY_CUSTOMER 
WHERE O_CUSTKEY = 7918018
->>
SELECT "partitionsTotal", "partitionsAssigned"
FROM $1
WHERE "operation" = 'GlobalStats';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 4 │ Measure a direct MV read
-- ──────────────────────────────────────────────────────────────────────────────

EXECUTE TASK OPS.TASK_RESTART_LAB16_WH;
-- STOP: wait for this task run to SUCCEED in Snowsight before continuing.

SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS ORDER_AMOUNT
FROM PERF.MVW_BY_CUSTOMER 
WHERE O_CUSTKEY = 7918018;

SET MV_DIRECT_QUERY_ID = LAST_QUERY_ID();

SELECT * 
FROM TABLE(GET_QUERY_OPERATOR_STATS($MV_DIRECT_QUERY_ID));

-- CHECKPOINT (QA rehearsal, X-Small, cold): 18 orders, 2467651.95;
-- Materialized View Scan scanned 1/56, 2490448 bytes. Compare Step 2.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 5 │ Observe rewrite and column coverage
-- ──────────────────────────────────────────────────────────────────────────────

-- This query still names the base table. Inspect EXPLAIN and the profile:
-- Snowflake can choose the MV without changing the query. A no-rewrite is
-- valid; never infer a rewrite merely because the result is correct.
EXPLAIN
SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS ORDER_AMOUNT
FROM PERF.TPCH_ORDERS_BY_DATE 
WHERE O_CUSTKEY = 7918018;

EXECUTE TASK OPS.TASK_RESTART_LAB16_WH;
-- STOP: wait for this task run to SUCCEED in Snowsight before continuing.

SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS ORDER_AMOUNT
FROM PERF.TPCH_ORDERS_BY_DATE 
WHERE O_CUSTKEY = 7918018;

SET CUSTOMER_AFTER_QUERY_ID = LAST_QUERY_ID();

SELECT * 
FROM TABLE(GET_QUERY_OPERATOR_STATS($CUSTOMER_AFTER_QUERY_ID));

-- CHECKPOINT (QA rehearsal, X-Small, cold): 18 orders, 2467651.95; EXPLAIN
-- chose MVW_BY_CUSTOMER, assigned 1/56; profile scanned 1/56, 2490448 bytes.
-- Optimizer choices can differ; record actual target, query ID and elapsed time.

-- Compare a covered projection with SELECT *, which asks for base columns
-- omitted from the MV. Inspect the objects in both plans; do not assume the
-- optimizer must choose an MV merely because the needed columns are present.
EXPLAIN
SELECT O_ORDERKEY, O_CUSTKEY, O_ORDERDATE, O_TOTALPRICE -- all these columns are projected in the MVW_BY_CUSTOMER
FROM PERF.TPCH_ORDERS_BY_DATE 
WHERE O_CUSTKEY = 7918018
->>
EXPLAIN
SELECT * -- not all columns are available in MVW_BY_CUSTOMER 
FROM PERF.TPCH_ORDERS_BY_DATE 
WHERE O_CUSTKEY = 7918018
->>
SELECT 'COVERED PROJECTION' AS CASE_NAME, "operation", "objects",
       "partitionsAssigned", "partitionsTotal"
FROM $2 WHERE "operation" IN ('TableScan', 'Materialized View Scan')
UNION ALL
SELECT 'ALL COLUMNS', "operation", "objects",
       "partitionsAssigned", "partitionsTotal"
FROM $1 WHERE "operation" IN ('TableScan', 'Materialized View Scan');

-- CHECKPOINT (QA rehearsal): covered projection chose MVW_BY_CUSTOMER 1/56;
-- SELECT * used the base table 135/135. Plan choices and counts may vary.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 6 │ Account for cost and stop background maintenance and compute
-- ──────────────────────────────────────────────────────────────────────────────

-- SHOW reports extra storage in bytes, not a price. The copy and MV consume
-- storage; MV refresh and clustering consume serverless resources. Compare
-- these costs with query savings and the frequency of the access pattern.
SHOW MATERIALIZED VIEWS LIKE 'MVW_BY_CUSTOMER' IN SCHEMA PERF;

-- STOP even if an earlier measurement failed or class ends early. The owner
-- suspends MV use, maintenance and reclustering. Storage remains. RESUME
-- re-enables all three and can incur catch-up costs.
ALTER MATERIALIZED VIEW PERF.MVW_BY_CUSTOMER SUSPEND;

SHOW MATERIALIZED VIEWS LIKE 'MVW_BY_CUSTOMER' IN SCHEMA PERF;
-- CHECKPOINT: invalid=true and invalid_reason indicates manual suspension.
-- automatic_clustering can still display ON: MV suspension implicitly stops it.
-- If cleanup fails, resolve it before leaving; the course stop script also
-- identifies this MV.

-- First confirm any restart task run has finished in Snowsight; dropping the
-- task or procedure during a run can interrupt cleanup or restart the warehouse.
DROP TASK IF EXISTS OPS.TASK_RESTART_LAB16_WH;
DROP PROCEDURE IF EXISTS OPS.SP_RESTART_LAB16_WH(INTEGER);

-- Drop the dedicated warehouse even if the lab ends before the MV is created.
-- ACCOUNTADMIN created it, so switch back to that role to drop it.
USE WAREHOUSE ADV_WH;
USE ROLE ACCOUNTADMIN;

DROP WAREHOUSE IF EXISTS LAB16_WH;
SHOW WAREHOUSES LIKE 'LAB16_WH';
-- CHECKPOINT: LAB16_WH is absent. The table and suspended MV still use storage.
USE ROLE ADV_LAB;

-- Optional-QAS.sql is the separate query acceleration estimate and experiment.