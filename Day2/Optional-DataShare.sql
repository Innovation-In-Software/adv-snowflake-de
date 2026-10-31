/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
Optional account-sharing branch — prepared consumer account only
1) Expose a narrow aggregate with the required share privileges
2) Verify the consumer account imports the share
3) Distinguish sharing from copying or Iceberg REST access
----------------------------------------------------------------------------------*/

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY2';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Producer: prepare a share without adding any consumer yet
-- ──────────────────────────────────────────────────────────────────────────────

-- Optional branch; execute only after a second authorized training account exists.

USE ROLE ACCOUNTADMIN;

CREATE SHARE ADV_US_METRICS_SHARE;

GRANT USAGE ON DATABASE ADV_ORDERS TO SHARE ADV_US_METRICS_SHARE;

GRANT USAGE ON SCHEMA ADV_ORDERS.CONSUMER TO SHARE ADV_US_METRICS_SHARE;

GRANT SELECT ON VIEW ADV_ORDERS.CONSUMER.SHARE_US_METRICS
    TO SHARE ADV_US_METRICS_SHARE;

SHOW GRANTS TO SHARE ADV_US_METRICS_SHARE;

-- Deliberately commented: replace approved identifiers during rehearsal.
-- ALTER SHARE ADV_US_METRICS_SHARE ADD ACCOUNTS = <organization.account>;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Consumer: import and query in the second account
-- ──────────────────────────────────────────────────────────────────────────────

-- Execute these adapted statements in the PREPARED CONSUMER account, not here.
-- SHOW SHARES;
-- CREATE DATABASE ADV_SHARED_US FROM SHARE <producer_org.producer_account>.ADV_US_METRICS_SHARE;
-- SELECT * FROM ADV_SHARED_US.CONSUMER.SHARE_US_METRICS;
-- Expected US / 2 / 165. Record both account IDs and query IDs without secrets.
-- Provider cleanup: remove the consumer and drop only this lab-created share.
-- DROP SHARE ADV_US_METRICS_SHARE;

USE ROLE ADV_LAB;
