/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
1) Provision an isolated role, warehouse and database
2) Create Bronze, Silver, Gold and operational schemas
3) Verify the session context before starting the labs
----------------------------------------------------------------------------------*/

-- Advanced Snowflake | Day 1 | 00: identical isolated learning environments
-- Run one section at a time; account-specific readiness still applies.
-- Use a NEW dedicated training account.
-- Rerunning this script resets ADV_WH and ADV_ORDERS, including all lab data
-- and database objects. After setup completes, restart the labs from Lab 01.
-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1: Everyone provisions the same limited lab role using their trial admin.
-- ──────────────────────────────────────────────────────────────────────────────
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS ADV_LAB;

SET student_user = CURRENT_USER();
GRANT ROLE ADV_LAB TO USER IDENTIFIER($student_user);

CREATE OR REPLACE WAREHOUSE ADV_WH
 WAREHOUSE_SIZE='XSMALL' 
 ENABLE_QUERY_ACCELERATION=FALSE
 AUTO_SUSPEND=60
 AUTO_RESUME=TRUE 
 INITIALLY_SUSPENDED=TRUE;
 
CREATE OR REPLACE DATABASE ADV_ORDERS;

GRANT OWNERSHIP ON DATABASE ADV_ORDERS TO ROLE ADV_LAB COPY CURRENT GRANTS; --Preserves existing grants on that database during the ownership transfer.

GRANT USAGE, OPERATE ON WAREHOUSE ADV_WH TO ROLE ADV_LAB;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE ADV_LAB;
-- Lab 04 uses a serverless root task; its owner needs this additional privilege.
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE ADV_LAB;

GRANT MODIFY LOG EVENT LEVEL ON ACCOUNT TO ROLE ADV_LAB;

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

/*
--------------------------------------------------------------------------------
LOCAL WORKSTATION SETUP — PAUSE HERE BEFORE CONTINUING
--------------------------------------------------------------------------------

1. Make sure you have cloned the ENTIRE course repository to your local
   workstation. The repository root must contain .env.example and the SetUp
   folder. A Snowflake Git Workspace alone is not the local folder needed here.

2. In the repository root, copy .env.example to a file named .env. Edit .env
   and set these three values:

       SNOWFLAKE_ACCOUNT=<your Snowflake account identifier>
       SNOWFLAKE_USER=<your Snowflake username>
       SNOWFLAKE_PASSWORD=<your Snowflake password>

   Leave the classroom defaults for role, warehouse, database, schema and key
   path. Do not commit or share .env.

3. Make sure Python is installed. From a terminal opened in the repository
   root, install the required packages:

       python -m pip install -r SetUp/requirements.txt

4. Verify username/password connectivity before changing the user's
   authentication configuration:

       python SetUp/test_connection.py

   Continue only after the script confirms the connected user and account.

5. Generate and register a key pair:

       python SetUp/key_pair_setup.py

   This script saves an unencrypted private key outside the repository, then
   connects as ACCOUNTADMIN and registers its public key on your user. It does
   not print your password. Keep the private key private. Windows is the
   supported class setup; ask the instructor for help if using another OS.
--------------------------------------------------------------------------------
*/
