/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
C8 — Data quality and pipeline observability
1) Separate business-state correctness from execution success
2) Evaluate deterministic quality checks and a custom metric
3) Observe scheduled metric evidence and stop serverless monitoring
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 10 - Quality and observability.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY2';

-- SETUP: define a separate quality-test destination before creating metrics.
-- The metric will inspect this table; it must never damage the course orders.

CREATE TABLE OPS.DQ_DEMO (AMOUNT NUMBER(12, 2));

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Run immediate SQL quality controls
-- ──────────────────────────────────────────────────────────────────────────────

SELECT 'NULL_ORDER_ID' AS CHECK_NAME, COUNT_IF(ORDER_ID IS NULL) AS FAILURES FROM SILVER.ORDERS_CURRENT
UNION ALL
SELECT 'DUPLICATE_ORDER_ID', COUNT(*) - COUNT(DISTINCT ORDER_ID) FROM SILVER.ORDERS_CURRENT
UNION ALL
SELECT 'NEGATIVE_AMOUNT', COUNT_IF(AMOUNT < 0) FROM SILVER.ORDERS_CURRENT;

-- CHECKPOINT: zero failures in each control.

SELECT REJECT_REASON, COUNT(*) AS REJECTED_ROWS FROM SILVER.REJECTED_EVENTS GROUP BY REJECT_REASON;

-- CHECKPOINT: BAD_AMOUNT / 1; a rejection is preserved evidence, not a silent loss.

SELECT COUNT(*) AS RAW_ROWS FROM BRONZE.EVENTS_RAW;

SELECT COUNT(*) AS INBOX_ROWS FROM SILVER.EVENT_INBOX;

SELECT COUNT(*) AS PENDING_ROWS FROM BRONZE.EVENTS_STREAM;

-- Full Day 1 including Snowpark replay: raw/inbox 11, pending 0.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Evaluate a custom data metric before scheduling it
-- ──────────────────────────────────────────────────────────────────────────────

-- Enterprise account and DMF privileges required; validate this for the whole class.

USE ROLE ACCOUNTADMIN;

GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE ADV_LAB;

GRANT APPLICATION ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER TO ROLE ADV_LAB;

USE ROLE ADV_LAB;

CREATE DATA METRIC FUNCTION GOVERNANCE.NEGATIVE_AMOUNT_COUNT
    (ARG_T TABLE(ARG_C NUMBER(12, 2)))
RETURNS NUMBER
AS 'SELECT COUNT_IF(ARG_C < 0) FROM ARG_T';

SELECT GOVERNANCE.NEGATIVE_AMOUNT_COUNT(
    SELECT AMOUNT FROM SILVER.ORDERS_CURRENT) AS NEGATIVE_AMOUNTS;

-- CHECKPOINT: 0. A direct call validates the metric logic immediately.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Demonstrate monitoring on a separate quality fixture
-- ──────────────────────────────────────────────────────────────────────────────

-- Never damage the course orders merely to make a monitoring result interesting.

INSERT INTO OPS.DQ_DEMO VALUES (10), (-5), (NULL);

SELECT GOVERNANCE.NEGATIVE_AMOUNT_COUNT(SELECT AMOUNT FROM OPS.DQ_DEMO);

-- CHECKPOINT: 1. NULL handling is a separate quality rule.

ALTER TABLE OPS.DQ_DEMO SET DATA_METRIC_SCHEDULE = '5 MINUTE';

ALTER TABLE OPS.DQ_DEMO ADD DATA METRIC FUNCTION
    GOVERNANCE.NEGATIVE_AMOUNT_COUNT ON (AMOUNT);

SELECT * FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
    REF_ENTITY_NAME => 'ADV_ORDERS.OPS.DQ_DEMO', REF_ENTITY_DOMAIN => 'TABLE'));

SELECT * FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
WHERE TABLE_DATABASE = 'ADV_ORDERS' AND TABLE_NAME = 'DQ_DEMO'
ORDER BY MEASUREMENT_TIME DESC;

-- Scheduled results are asynchronous and may not appear in five exact minutes.
-- Wait for a matching metric/measurement row, not merely successful association DDL.
-- If service/edition/privilege blocks this branch, record BLOCKED and retain
-- direct SQL/metric evidence. Do not claim the scheduled objective passed.

ALTER TABLE OPS.DQ_DEMO DROP DATA METRIC FUNCTION
    GOVERNANCE.NEGATIVE_AMOUNT_COUNT ON (AMOUNT);

ALTER TABLE OPS.DQ_DEMO UNSET DATA_METRIC_SCHEDULE;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 4 │ Inspect execution and freshness independently
-- ──────────────────────────────────────────────────────────────────────────────

SELECT NAME, STATE, ERROR_MESSAGE, QUERY_ID, SCHEDULED_TIME, COMPLETED_TIME
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(RESULT_LIMIT => 100))
WHERE DATABASE_NAME = 'ADV_ORDERS' ORDER BY SCHEDULED_TIME DESC;

SELECT * FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
    NAME_PREFIX => 'ADV_ORDERS.GOLD', RESULT_LIMIT => 100));

SELECT * FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 100)) ORDER BY START_TIME DESC;

-- Correlate query IDs, object state and business totals. Account Usage views can
-- have latency; session history is useful for immediate classroom troubleshooting.
