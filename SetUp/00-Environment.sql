/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
1) Provision an isolated role, warehouse and database
2) Create Bronze, Silver, Gold and operational schemas
3) Verify the session context before starting the labs
----------------------------------------------------------------------------------*/

-- Advanced Snowflake | Day 1 | 00: identical isolated learning environments
-- Run one section at a time; account-specific readiness still applies.
-- Use a NEW dedicated training account.
-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1: Everyone provisions the same limited lab role using their trial admin.
-- ──────────────────────────────────────────────────────────────────────────────
USE ROLE ACCOUNTADMIN;

CREATE ROLE ADV_LAB;

SET student_user = CURRENT_USER();
GRANT ROLE ADV_LAB TO USER IDENTIFIER($student_user);

CREATE WAREHOUSE ADV_WH 
 WAREHOUSE_SIZE='XSMALL' 
 ENABLE_QUERY_ACCELERATION=FALSE
 AUTO_SUSPEND=60
 AUTO_RESUME=TRUE 
 INITIALLY_SUSPENDED=TRUE;
 
CREATE DATABASE ADV_ORDERS;

GRANT OWNERSHIP ON DATABASE ADV_ORDERS TO ROLE ADV_LAB COPY CURRENT GRANTS; --Preserves existing grants on that database during the ownership transfer.

GRANT USAGE, OPERATE ON WAREHOUSE ADV_WH TO ROLE ADV_LAB;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE ADV_LAB;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2: All data work now runs as ADV_LAB, including task ownership.
-- ──────────────────────────────────────────────────────────────────────────────
USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;

CREATE SCHEMA BRONZE;
CREATE SCHEMA SILVER;
CREATE SCHEMA GOLD;
CREATE SCHEMA OPS;  -- Operations schema - for control and monitoring of the training pipeline(s)

ALTER SESSION SET TIMEZONE='UTC';  --zero-offset reference time zone (+00:00) - to ensure consistent timestamps across all students

ALTER SESSION SET QUERY_TAG='ADV_2026_DAY1';
-- This assigns the label ADV_2026_DAY1 to subsequent SQL statements executed in your current Snowflake session. 
-- Snowflake records that label in the QUERY_TAG column of query history, so you can find and group those statements later.

SELECT
    CURRENT_ACCOUNT(),
    CURRENT_REGION(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE();
	
-- ──────────────────────────────────────────────────────────────────────────────
-- CHECKPOINT: role ADV_LAB, warehouse ADV_WH. 
-- ──────────────────────────────────────────────────────────────────────────────


SHOW ACCOUNTS ->>
SELECT *
FROM (
  SELECT "organization_name", "account_name", "organization_name" || '-' || "account_name" as "account_id", 
         "account_locator", "account_url", "account_locator_url", current_user() as "user_name", 
         'https://app.snowflake.com/' || LOWER("organization_name") || '/' || LOWER("account_name") AS "snowsight_url",
         REGEXP_REPLACE("snowflake_region", '^AWS_([A-Z]+)_([A-Z]+)_([0-9]+)$', '\\1-\\2-\\3') AS "account_region"
  FROM $1
)
UNPIVOT (
  value FOR key IN (
    "organization_name",
    "account_name",
    "account_id",
    "account_locator",
    "account_region",
    "account_url",
    "account_locator_url",
    "snowsight_url",
    "user_name"
  )
);


-- Find our tagged statements from the last hour.
-- executed after QUERY_TAG was set.

SELECT QUERY_ID, START_TIME, QUERY_TAG, EXECUTION_STATUS, QUERY_TEXT
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 100))
WHERE QUERY_TAG = 'ADV_2026_DAY1'
  AND START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;