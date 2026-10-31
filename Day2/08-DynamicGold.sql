/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
C6 — Dynamic Gold and actual refresh evidence
1) Create a declarative Gold pipeline from validated Silver
2) Inspect refresh mode, freshness and history
3) Reconcile task-maintained state with Dynamic Table results
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 08 - Declarative Dynamic Gold.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY2';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Create two Dynamic Tables with explicit roles and freshness goals
-- ──────────────────────────────────────────────────────────────────────────────

-- Gold stores enriched detail first; metrics depend on that detail.
-- Policy controls will be applied at the consumer boundary, not the source.

CREATE TABLE SILVER.ORDER_CONTACTS
(
    ORDER_ID STRING,
    EMAIL    STRING
);

INSERT INTO SILVER.ORDER_CONTACTS VALUES
    ('o1', 'owner-o1@example.invalid'),
    ('o2', 'owner-o2@example.invalid'),
    ('o3', 'owner-o3@example.invalid');

CREATE DYNAMIC TABLE GOLD.ORDER_DETAIL_DT
    TARGET_LAG  = DOWNSTREAM
    WAREHOUSE   = ADV_WH
    REFRESH_MODE = INCREMENTAL
    INITIALIZE  = ON_CREATE
AS
SELECT O.ORDER_ID, O.EVENT_ID, O.VERSION, O.EVENT_TIME, O.STATUS,
       O.AMOUNT, O.REGION, C.EMAIL
FROM SILVER.ORDERS_CURRENT O
LEFT JOIN SILVER.ORDER_CONTACTS C ON O.ORDER_ID = C.ORDER_ID;

CREATE DYNAMIC TABLE GOLD.ORDER_METRICS_DT
    TARGET_LAG  = '5 minutes'
    WAREHOUSE   = ADV_WH
    REFRESH_MODE = INCREMENTAL
    INITIALIZE  = ON_CREATE
AS
SELECT REGION, COUNT(*) AS ACTIVE_ORDERS, SUM(AMOUNT) AS ACTIVE_AMOUNT_USD
FROM GOLD.ORDER_DETAIL_DT
WHERE STATUS <> 'CANCELLED'
GROUP BY REGION;

-- INITIALIZE ON_CREATE makes initial creation wait for initialization.
-- A five-minute target is a staleness goal, not a fixed timer or guarantee.

SHOW DYNAMIC TABLES IN SCHEMA GOLD;

SELECT * FROM GOLD.ORDER_METRICS_DT;

-- CHECKPOINT: US / 2 / 165; no active EU orders.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Compare exact values and inspect refresh history
-- ──────────────────────────────────────────────────────────────────────────────

SELECT REGION, ACTIVE_ORDERS, ACTIVE_AMOUNT_USD FROM GOLD.ORDER_METRICS_DT
MINUS
SELECT REGION, ACTIVE_ORDERS, ACTIVE_AMOUNT_USD FROM GOLD.ORDER_METRICS;

SELECT REGION, ACTIVE_ORDERS, ACTIVE_AMOUNT_USD FROM GOLD.ORDER_METRICS
MINUS
SELECT REGION, ACTIVE_ORDERS, ACTIVE_AMOUNT_USD FROM GOLD.ORDER_METRICS_DT;

-- CHECKPOINT: both differences empty.

SELECT NAME, STATE, STATE_CODE, STATE_MESSAGE, REFRESH_START_TIME, REFRESH_END_TIME
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
    NAME_PREFIX => 'ADV_ORDERS.GOLD', RESULT_LIMIT => 100))
ORDER BY REFRESH_START_TIME DESC;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Make a reversible source correction and observe convergence
-- ──────────────────────────────────────────────────────────────────────────────

-- Teaching update targets Silver directly to isolate DT maintenance.
-- Restore it before returning to the event pipeline; do not call APPLY_EVENTS here.

UPDATE SILVER.ORDERS_CURRENT SET AMOUNT = 135 WHERE ORDER_ID = 'o1';

ALTER DYNAMIC TABLE GOLD.ORDER_DETAIL_DT REFRESH;

ALTER DYNAMIC TABLE GOLD.ORDER_METRICS_DT REFRESH;

SELECT * FROM GOLD.ORDER_METRICS_DT;

-- CHECKPOINT after refresh: US / 2 / 180. Requery/history if refresh is still active.

UPDATE SILVER.ORDERS_CURRENT SET AMOUNT = 120 WHERE ORDER_ID = 'o1';

ALTER DYNAMIC TABLE GOLD.ORDER_DETAIL_DT REFRESH;

ALTER DYNAMIC TABLE GOLD.ORDER_METRICS_DT REFRESH;

SELECT * FROM GOLD.ORDER_METRICS_DT;

-- CHECKPOINT restored: US / 2 / 165. Owner ADV_LAB retains source privileges.
-- Optional practice: inspect/change target lag, then restore the five-minute goal.
