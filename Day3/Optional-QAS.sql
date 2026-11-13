/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
Optional — Query Acceleration Service (QAS)
1) Compare ineligible and eligible sample-data queries
2) Run the eligible query with QAS off and on
3) Inspect actual service usage, performance and cost
----------------------------------------------------------------------------------*/

-- QAS requires Enterprise Edition and access to SNOWFLAKE_SAMPLE_DATA
-- TPCH_SF1 and TPCH_SF1000. This independent experiment uses its own
-- warehouse and does not change the main pipeline or Lab 16's objects.
-- The SF1000 query scans a large table and can take over a minute.

USE ROLE ACCOUNTADMIN;

-- If this warehouse already exists, CREATE fails. Stop and confirm ownership
-- before using or dropping it; it may belong to another workload.
CREATE WAREHOUSE ADV_QAS_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    ENABLE_QUERY_ACCELERATION = FALSE;

GRANT USAGE, OPERATE, MODIFY ON WAREHOUSE ADV_QAS_WH TO ROLE ADV_LAB;

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_QAS_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3_QAS';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ An ineligible query
-- ──────────────────────────────────────────────────────────────────────────────

SELECT COUNT(*) AS ORDER_COUNT
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 42;
SET QAS_SMALL_ID = LAST_QUERY_ID();

SELECT PARSE_JSON(SYSTEM$ESTIMATE_QUERY_ACCELERATION($QAS_SMALL_ID)) AS ESTIMATE;
-- QA checkpoint: status = ineligible; ineligibleReason = NO_LARGE_ENOUGH_SCAN.
-- Results and eligibility depend on Snowflake's plan and may differ.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Find an eligible scan with QAS disabled
-- ──────────────────────────────────────────────────────────────────────────────

-- Suspend fully to clear warehouse cache, then resume. Execute these statements
-- individually: if already SUSPENDED skip SUSPEND; repeat SHOW until it says
-- SUSPENDED before RESUME. Restarting incurs a warehouse startup charge.
ALTER WAREHOUSE ADV_QAS_WH SUSPEND;
SHOW WAREHOUSES LIKE 'ADV_QAS_WH';
-- STOP: wait for SUSPENDED before resuming.
ALTER WAREHOUSE ADV_QAS_WH RESUME;

SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS TOTAL_PRICE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.ORDERS
WHERE O_COMMENT ILIKE '%unusual%';
SET QAS_OFF_ID = LAST_QUERY_ID();

SELECT PARSE_JSON(SYSTEM$ESTIMATE_QUERY_ACCELERATION($QAS_OFF_ID)) AS ESTIMATE;
SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS($QAS_OFF_ID));

-- QA checkpoint (X-Small): 139059160 orders, 21014105742415.10 total;
-- status = eligible; estimate at scale factor 2 = 28 seconds.
-- This is an estimate, not guaranteed performance. Confirm the scan's
-- percentage_scanned_from_cache is 0 for a cold-cache comparison.
-- STOP/GO: continue only if this run is eligible. If not, record the reason
-- and proceed to Step 4 cleanup; eligibility can vary by account and run.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Run the same query with QAS enabled
-- ──────────────────────────────────────────────────────────────────────────────

-- The scale factor bounds additional serverless compute at 2 times the
-- warehouse size. QAS incurs separate charges when used.
ALTER WAREHOUSE ADV_QAS_WH SET
    ENABLE_QUERY_ACCELERATION = TRUE
    QUERY_ACCELERATION_MAX_SCALE_FACTOR = 2;

ALTER WAREHOUSE ADV_QAS_WH SUSPEND;
SHOW WAREHOUSES LIKE 'ADV_QAS_WH';
-- STOP: wait for SUSPENDED before resuming.
ALTER WAREHOUSE ADV_QAS_WH RESUME;

SELECT COUNT(*) AS ORDER_COUNT, SUM(O_TOTALPRICE) AS TOTAL_PRICE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.ORDERS
WHERE O_COMMENT ILIKE '%unusual%';
SET QAS_ON_ID = LAST_QUERY_ID();

SELECT * FROM TABLE(GET_QUERY_OPERATOR_STATS($QAS_ON_ID));

-- Compare results with Step 2 and verify cache percentage. Inspect both query
-- profiles and the query history below: positive QAS partitions/bytes show
-- actual service work. Eligibility and a faster runtime do not prove QAS ran.
-- In one QA run, QAS off took 67 seconds; QAS on took 29 seconds and
-- scanned 1,984 partitions through the service. Your results may differ.
SELECT QUERY_ID, TOTAL_ELAPSED_TIME, EXECUTION_TIME, BYTES_SCANNED,
       QUERY_ACCELERATION_BYTES_SCANNED,
       QUERY_ACCELERATION_PARTITIONS_SCANNED, QUERY_ACCELERATION_UPPER_LIMIT_SCALE_FACTOR
FROM TABLE(ADV_ORDERS.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 100))
WHERE QUERY_ID IN ($QAS_OFF_ID, $QAS_ON_ID);

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 4 │ Cleanup and cost
-- ──────────────────────────────────────────────────────────────────────────────

-- If stopping early, run cleanup even when Step 3 was skipped. The X-Small
-- warehouse and any QAS resources used are billed separately; inspect Cost
-- Management > Consumption > Query Acceleration for actual service credits.
ALTER WAREHOUSE ADV_QAS_WH SET ENABLE_QUERY_ACCELERATION = FALSE;
USE WAREHOUSE ADV_WH;
USE ROLE ACCOUNTADMIN;
DROP WAREHOUSE IF EXISTS ADV_QAS_WH;
SHOW WAREHOUSES LIKE 'ADV_QAS_WH';
-- CHECKPOINT: no ADV_QAS_WH row.
USE ROLE ADV_LAB;
