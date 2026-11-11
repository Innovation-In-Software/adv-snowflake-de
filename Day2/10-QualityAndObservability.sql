/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
-— Data quality and pipeline observability
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

CREATE OR REPLACE TABLE OPS.DQ_DEMO (AMOUNT NUMBER(12, 2));

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Run immediate SQL quality controls
-- ──────────────────────────────────────────────────────────────────────────────

SELECT 'NULL_ORDER_ID' AS CHECK_NAME, 
        COUNT_IF(ORDER_ID IS NULL) AS FAILURES 
FROM SILVER.ORDERS_CURRENT
UNION ALL
SELECT 'DUPLICATE_ORDER_ID', 
        COUNT(*) - COUNT(DISTINCT ORDER_ID) 
FROM SILVER.ORDERS_CURRENT
UNION ALL
SELECT 'NEGATIVE_AMOUNT', 
        COUNT_IF(AMOUNT < 0) 
FROM SILVER.ORDERS_CURRENT;

-- CHECKPOINT: zero failures in each control.

SELECT REJECT_REASON, COUNT(*) AS REJECTED_ROWS 
FROM SILVER.VW_REJECTED_EVENTS 
GROUP BY REJECT_REASON;

-- CHECKPOINT: BAD_AMOUNT / 1; a rejection is preserved evidence, not a silent loss.

SELECT COUNT(*) AS RAW_ROWS FROM BRONZE.EVENTS_RAW;

SELECT COUNT(*) AS INBOX_ROWS FROM SILVER.EVENT_INBOX;

SELECT COUNT(*) AS PENDING_ROWS FROM BRONZE.EVENTS_STREAM;

-- Full Day 1 including Lab 02A and Snowpark replay: raw/inbox 15, pending 0.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Evaluate a custom data metric before scheduling it
-- ──────────────────────────────────────────────────────────────────────────────

-- Enterprise account and DMF privileges required; validate this for the whole class.

USE ROLE ACCOUNTADMIN;

GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE ADV_LAB;

-- Give our ADV_LAB role Snowflake’s predefined permissions for viewing data-quality monitoring results
-- APPLICATION ROLE identifies a role supplied by an application, rather than an ordinary account role.
GRANT APPLICATION ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER TO ROLE ADV_LAB;

USE ROLE ADV_LAB;

CREATE DATA METRIC FUNCTION GOVERNANCE.NEGATIVE_AMOUNT_COUNT(ARG_T TABLE(ARG_C NUMBER(12, 2) ))
RETURNS NUMBER
AS 
'SELECT COUNT_IF(ARG_C < 0) FROM ARG_T';

-- This DMF demonstrates monitoring alongside the pipeline.
-- First, we check real Silver data and expect zero negative amounts.
-- Then, we use DQ_DEMO to produce a known violation and observe
-- a scheduled monitoring result.
-- In production, we could associate this metric with ORDERS_CURRENT.
-- We detach it from the demo table afterward to stop background monitoring.

SELECT GOVERNANCE.NEGATIVE_AMOUNT_COUNT(SELECT AMOUNT FROM SILVER.ORDERS_CURRENT) AS NEGATIVE_AMOUNTS;

-- CHECKPOINT: 0. A direct call validates the metric logic immediately.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Demonstrate monitoring on a separate quality fixture
-- ──────────────────────────────────────────────────────────────────────────────

-- Never damage the course orders merely to make a monitoring result interesting.

INSERT INTO OPS.DQ_DEMO VALUES (10), (-5), (NULL);

SELECT GOVERNANCE.NEGATIVE_AMOUNT_COUNT(SELECT AMOUNT FROM OPS.DQ_DEMO); --or:
SELECT GOVERNANCE.NEGATIVE_AMOUNT_COUNT(SELECT * FROM OPS.DQ_DEMO);

-- CHECKPOINT: 1. NULL handling is a separate quality rule.

ALTER TABLE OPS.DQ_DEMO SET DATA_METRIC_SCHEDULE = '5 MINUTE';

ALTER TABLE OPS.DQ_DEMO ADD DATA METRIC FUNCTION GOVERNANCE.NEGATIVE_AMOUNT_COUNT ON (AMOUNT);

SELECT * 
FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(REF_ENTITY_NAME => 'ADV_ORDERS.OPS.DQ_DEMO', REF_ENTITY_DOMAIN => 'TABLE'));

SELECT * 
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
WHERE TABLE_DATABASE = 'ADV_ORDERS' 
  AND TABLE_NAME = 'DQ_DEMO'
ORDER BY MEASUREMENT_TIME DESC;

-- Scheduled results are asynchronous and may not appear in five exact minutes.
-- Wait for a matching metric/measurement row, not merely successful association DDL.
-- If service/edition/privilege blocks this branch, record BLOCKED and retain
-- direct SQL/metric evidence. Do not claim the scheduled objective passed.

ALTER TABLE OPS.DQ_DEMO DROP DATA METRIC FUNCTION GOVERNANCE.NEGATIVE_AMOUNT_COUNT ON (AMOUNT);

ALTER TABLE OPS.DQ_DEMO UNSET DATA_METRIC_SCHEDULE;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 4 │ Inspect execution and freshness independently
-- ──────────────────────────────────────────────────────────────────────────────

SELECT NAME, STATE, ERROR_MESSAGE, QUERY_ID, SCHEDULED_TIME, COMPLETED_TIME
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(RESULT_LIMIT => 100))
WHERE DATABASE_NAME = 'ADV_ORDERS' 
ORDER BY SCHEDULED_TIME DESC;

SELECT * 
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(NAME_PREFIX => 'ADV_ORDERS.GOLD', RESULT_LIMIT => 100));

SELECT * 
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 100)) 
ORDER BY START_TIME DESC;

-- Correlate query IDs, object state and business totals. Account Usage views can
-- have latency; session history is useful for immediate classroom troubleshooting.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 5 │ Validate a relationship between two columns
-- ──────────────────────────────────────────────────────────────────────────────
-- A DMF can inspect multiple columns together.
-- Business rule: a contract's end date must not precede its start date.
-- Use a separate demonstration table; the order pipeline is unchanged.

CREATE OR REPLACE TABLE OPS.DQ_CONTRACTS_DEMO
(
    CONTRACT_ID    STRING,
    CONTRACT_START DATE,
    CONTRACT_END   DATE
);

INSERT INTO OPS.DQ_CONTRACTS_DEMO 
VALUES
    ('c1', '2026-01-01', '2026-12-31'), -- Valid range
    ('c2', '2026-06-01', '2026-05-01'), -- Invalid: end before start
    ('c3', '2026-03-01', '2026-03-01'), -- Valid: same-day contract
    ('c4', '2026-04-01', NULL);         -- Not checked by this rule

CREATE OR REPLACE DATA METRIC FUNCTION GOVERNANCE.INVALID_DATE_RANGE_COUNT(
        ARG_T TABLE(START_DATE DATE, END_DATE DATE)
    )
RETURNS NUMBER
AS
$$
    SELECT COUNT(*)
    FROM ARG_T
    WHERE END_DATE < START_DATE
$$;

-- Input columns map by position:
-- CONTRACT_START becomes START_DATE; CONTRACT_END becomes END_DATE.
-- The function returns one numeric metric for the entire input.

SELECT GOVERNANCE.INVALID_DATE_RANGE_COUNT(
    SELECT CONTRACT_START, CONTRACT_END
    FROM OPS.DQ_CONTRACTS_DEMO
) AS INVALID_DATE_RANGES;

-- CHECKPOINT: 1.
-- NULL dates do not satisfy END_DATE < START_DATE.
-- Required-date validation would be a separate rule.

-- The metric tells us HOW MANY violations exist.
-- A diagnostic query shows WHICH records violate the rule.

SELECT *
FROM OPS.DQ_CONTRACTS_DEMO
WHERE CONTRACT_END < CONTRACT_START;

-- CHECKPOINT: c2 only.

-- Correct the known violation, then measure again.
-- The UPDATE performs the correction; the DMF only measures the result.

UPDATE OPS.DQ_CONTRACTS_DEMO
SET CONTRACT_END = '2026-06-30'
WHERE CONTRACT_ID = 'c2';

SELECT GOVERNANCE.INVALID_DATE_RANGE_COUNT(SELECT CONTRACT_START, CONTRACT_END FROM OPS.DQ_CONTRACTS_DEMO) AS INVALID_DATE_RANGES;

-- CHECKPOINT: 0.

-- This step calls the DMF directly.
-- The association and scheduling pattern from STEP 3 also applies:
-- ON (CONTRACT_START, CONTRACT_END).
-- No background monitoring is enabled by this demonstration.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 6 │ Evaluate built-in data metric functions
-- ──────────────────────────────────────────────────────────────────────────────
-- Snowflake provides system DMFs in SNOWFLAKE.CORE.
-- Use an existing system metric when it meets the requirement.
-- Create a custom DMF when your business rule needs additional logic.
--
-- Full catalog:
-- https://docs.snowflake.com/en/user-guide/data-quality-system-dmfs

CREATE OR REPLACE TABLE OPS.DQ_BUILTIN_DEMO
(
    RECORD_ID NUMBER,
    AMOUNT    NUMBER(12, 2)
);

INSERT INTO OPS.DQ_BUILTIN_DEMO 
VALUES
    (1,  10),
    (2,  10),
    (3,  -5),
    (4, NULL),
    (5,  25);

SELECT * FROM OPS.DQ_BUILTIN_DEMO ORDER BY RECORD_ID;

-- Completeness: how many amounts are missing?

SELECT SNOWFLAKE.CORE.NULL_COUNT(SELECT AMOUNT FROM OPS.DQ_BUILTIN_DEMO) AS NULL_AMOUNTS;

-- CHECKPOINT: 1.

-- Uniqueness: how many amounts belong to a duplicated value?
-- Both occurrences of 10 participate in the duplication.
-- Repeated amounts are not necessarily a business error;
-- this example demonstrates the metric's behavior.

SELECT SNOWFLAKE.CORE.DUPLICATE_COUNT(SELECT AMOUNT FROM OPS.DQ_BUILTIN_DEMO) AS DUPLICATE_AMOUNTS;

-- CHECKPOINT: 1.
-- The value 10 occurs twice, contributing one extra occurrence.

-- Validity: how many amounts are negative?
-- NULL is not counted as a negative value.

SELECT SNOWFLAKE.CORE.NEGATIVE_COUNT(SELECT AMOUNT FROM OPS.DQ_BUILTIN_DEMO) AS NEGATIVE_AMOUNTS;

-- CHECKPOINT: 1.
-- Our custom NEGATIVE_AMOUNT_COUNT demonstrates how to implement
-- a metric; this built-in function already covers that requirement.

-- Statistics: a DMF can return a measure other than a count.

SELECT SNOWFLAKE.CORE.MIN(SELECT AMOUNT FROM OPS.DQ_BUILTIN_DEMO) AS MINIMUM_AMOUNT,
       SNOWFLAKE.CORE.AVG(SELECT AMOUNT FROM OPS.DQ_BUILTIN_DEMO) AS AVERAGE_AMOUNT;

SELECT 

-- CHECKPOINT: -5 (min), 10 (avg)
-- NULL is excluded from the average.
-- Calculation: (10 + 10 - 5 + 25) / 4.

-- These are immediate calls, not scheduled associations.
-- No background monitoring is enabled by this step.
