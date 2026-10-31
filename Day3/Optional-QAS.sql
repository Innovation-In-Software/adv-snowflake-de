/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
Optional C11 branch — bounded QAS comparison
1) Use a separate warehouse with a bounded acceleration scale
2) Run an identical eligible query with QAS off and on
3) Record actual profile and cost evidence
----------------------------------------------------------------------------------*/

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Create a separate comparison warehouse
-- ──────────────────────────────────────────────────────────────────────────────

USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE ADV_QAS_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    ENABLE_QUERY_ACCELERATION = FALSE;

GRANT USAGE, OPERATE, MODIFY ON WAREHOUSE ADV_QAS_WH TO ROLE ADV_LAB;

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_QAS_WH;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT C.REGION, SUM(O.AMOUNT)
FROM PERF.ORDERS_BASE O JOIN PERF.CUSTOMERS C ON O.CUSTOMER_ID = C.CUSTOMER_ID
WHERE O.STATUS = 'PAID' GROUP BY C.REGION;

SET QAS_OFF_ID = LAST_QUERY_ID();

SELECT PARSE_JSON(SYSTEM$ESTIMATE_QUERY_ACCELERATION($QAS_OFF_ID));

-- Stop here if ineligible. Use the validated eligible workload selected at rehearsal.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Execute only an eligible workload with the service enabled
-- ──────────────────────────────────────────────────────────────────────────────

ALTER WAREHOUSE ADV_QAS_WH SET
    ENABLE_QUERY_ACCELERATION = TRUE
    QUERY_ACCELERATION_MAX_SCALE_FACTOR = 2;

SELECT C.REGION, SUM(O.AMOUNT)
FROM PERF.ORDERS_BASE O JOIN PERF.CUSTOMERS C ON O.CUSTOMER_ID = C.CUSTOMER_ID
WHERE O.STATUS = 'PAID' GROUP BY C.REGION;

SET QAS_ON_ID = LAST_QUERY_ID();

INSERT INTO PERF.MEASUREMENTS VALUES
    ('QAS_OFF', $QAS_OFF_ID, CURRENT_TIMESTAMP()),
    ('QAS_ON', $QAS_ON_ID, CURRENT_TIMESTAMP());

ALTER WAREHOUSE ADV_QAS_WH SET ENABLE_QUERY_ACCELERATION = FALSE;

ALTER WAREHOUSE ADV_QAS_WH SUSPEND;

USE WAREHOUSE ADV_WH;

-- A faster query without observed QAS usage does not establish QAS benefit.
