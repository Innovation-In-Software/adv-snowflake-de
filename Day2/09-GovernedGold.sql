/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
C7 — Governed Gold with explicit role tests
1) Grant consumers a narrow view without direct Bronze or Silver access
2) Apply masking and row access to the consumption boundary
3) Verify positive and negative access under isolated roles
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 09 - Governed consumption boundary.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY2';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Provision student-equivalent consumer roles
-- ──────────────────────────────────────────────────────────────────────────────

-- Run this short admin section in EVERY participant account.

USE ROLE ACCOUNTADMIN;

CREATE ROLE ADV_ANALYST_US;

CREATE ROLE ADV_ANALYST_EU;

CREATE ROLE ADV_AUDITOR;

SET STUDENT_USER = CURRENT_USER();

GRANT ROLE ADV_ANALYST_US TO USER IDENTIFIER($STUDENT_USER);

GRANT ROLE ADV_ANALYST_EU TO USER IDENTIFIER($STUDENT_USER);

GRANT ROLE ADV_AUDITOR TO USER IDENTIFIER($STUDENT_USER);

GRANT USAGE ON WAREHOUSE ADV_WH TO ROLE ADV_ANALYST_US;

GRANT USAGE ON WAREHOUSE ADV_WH TO ROLE ADV_ANALYST_EU;

GRANT USAGE ON WAREHOUSE ADV_WH TO ROLE ADV_AUDITOR;

USE ROLE ADV_LAB;
USE SECONDARY ROLES NONE;

GRANT USAGE ON DATABASE ADV_ORDERS TO ROLE ADV_ANALYST_US;

GRANT USAGE ON DATABASE ADV_ORDERS TO ROLE ADV_ANALYST_EU;

GRANT USAGE ON DATABASE ADV_ORDERS TO ROLE ADV_AUDITOR;

GRANT USAGE ON SCHEMA CONSUMER TO ROLE ADV_ANALYST_US;

GRANT USAGE ON SCHEMA CONSUMER TO ROLE ADV_ANALYST_EU;

GRANT USAGE ON SCHEMA CONSUMER TO ROLE ADV_AUDITOR;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Create a secure consumer view and its policies
-- ──────────────────────────────────────────────────────────────────────────────

-- Narrow view is the consumer contract. Source table remains owned by ADV_LAB.
-- Applying policies here separates consumer context from DT owner refresh context.

CREATE SECURE VIEW CONSUMER.ORDERS AS
SELECT ORDER_ID, EVENT_ID, VERSION, STATUS, AMOUNT, REGION, EMAIL FROM GOLD.ORDER_DETAIL_DT;

CREATE MASKING POLICY GOVERNANCE.EMAIL_MASK AS
    (VALUE STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ADV_LAB', 'ADV_AUDITOR') THEN VALUE
        ELSE '***MASKED***'
    END;

CREATE ROW ACCESS POLICY GOVERNANCE.REGION_ACCESS AS
    (ROW_REGION STRING) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('ADV_LAB', 'ADV_AUDITOR')
    OR (CURRENT_ROLE() = 'ADV_ANALYST_US' AND ROW_REGION = 'US')
    OR (CURRENT_ROLE() = 'ADV_ANALYST_EU' AND ROW_REGION = 'EU');

ALTER VIEW CONSUMER.ORDERS MODIFY COLUMN EMAIL
    SET MASKING POLICY GOVERNANCE.EMAIL_MASK;

ALTER VIEW CONSUMER.ORDERS ADD ROW ACCESS POLICY GOVERNANCE.REGION_ACCESS
    ON (REGION);

CREATE TAG GOVERNANCE.DATA_CLASSIFICATION
    ALLOWED_VALUES 'SYNTHETIC_CONTACT', 'BUSINESS_METRIC';

ALTER VIEW CONSUMER.ORDERS MODIFY COLUMN EMAIL
    SET TAG GOVERNANCE.DATA_CLASSIFICATION = 'SYNTHETIC_CONTACT';

GRANT SELECT ON VIEW CONSUMER.ORDERS TO ROLE ADV_ANALYST_US;

GRANT SELECT ON VIEW CONSUMER.ORDERS TO ROLE ADV_ANALYST_EU;

GRANT SELECT ON VIEW CONSUMER.ORDERS TO ROLE ADV_AUDITOR;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Test the role matrix with secondary roles disabled
-- ──────────────────────────────────────────────────────────────────────────────

USE ROLE ADV_ANALYST_US;
USE SECONDARY ROLES NONE;

SELECT CURRENT_ROLE(), ORDER_ID, REGION, EMAIL FROM CONSUMER.ORDERS ORDER BY ORDER_ID;

-- CHECKPOINT: o1/o3 only; both emails masked.

USE ROLE ADV_ANALYST_EU;
USE SECONDARY ROLES NONE;

SELECT CURRENT_ROLE(), ORDER_ID, STATUS, REGION, EMAIL FROM CONSUMER.ORDERS;

-- CHECKPOINT: o2 only, CANCELLED; email masked. Row authorization includes tombstones.

USE ROLE ADV_AUDITOR;
USE SECONDARY ROLES NONE;

SELECT CURRENT_ROLE(), ORDER_ID, REGION, EMAIL FROM CONSUMER.ORDERS ORDER BY ORDER_ID;

-- CHECKPOINT: all 3 rows; original example.invalid contact values.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 4 │ Verify a denied source read separately, then restore the engineer role
-- ──────────────────────────────────────────────────────────────────────────────

USE ROLE ADV_ANALYST_US;
USE SECONDARY ROLES NONE;

-- EXPECTED FAILURE: run this one statement separately and capture its error.
-- Stop-on-error tools must not execute this together with restoration statements.

SELECT * FROM ADV_ORDERS.SILVER.ORDERS_CURRENT;

-- After the expected failure, select and execute these statements independently.

USE ROLE ADV_LAB;
USE SECONDARY ROLES NONE;

SELECT * FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_NAME => 'ADV_ORDERS.CONSUMER.ORDERS', REF_ENTITY_DOMAIN => 'VIEW'));

-- SECURE VIEW does not by itself apply masking or region entitlements.
-- Optional practice: modify one role rule, verify it, then restore the original.
