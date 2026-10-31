/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
C9 — Consume governed Gold without widening access
1) Query a governed contract as each consumer role
2) Separate source freshness from authorization context
3) Prepare a narrowly owned hosted app and a safe share extension
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 11 - Consumers.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY2';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Consume the same contract under a consumer role
-- ──────────────────────────────────────────────────────────────────────────────

USE ROLE ADV_ANALYST_US;
USE SECONDARY ROLES NONE;

SELECT REGION, COUNT(*) AS ACTIVE_ORDERS, SUM(AMOUNT) AS ACTIVE_AMOUNT_USD
FROM CONSUMER.ORDERS
WHERE STATUS <> 'CANCELLED'
GROUP BY REGION;

-- CHECKPOINT: US / 2 / 165; contact values remain masked.

SELECT CURRENT_ROLE(), CURRENT_USER();

-- A client, notebook or app must be tested for its real execution role.
-- An application that executes as ADV_LAB can see every region; a view name
-- alone does not make an owner-rights application respect each viewer's roles.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Prepare an intentionally US-scoped hosted app
-- ──────────────────────────────────────────────────────────────────────────────

USE ROLE ADV_LAB;

GRANT CREATE STREAMLIT ON SCHEMA CONSUMER TO ROLE ADV_ANALYST_US;

-- Optional hosted notebook uses the same consumer role and view boundary.

GRANT CREATE NOTEBOOK ON SCHEMA CONSUMER TO ROLE ADV_ANALYST_US;

USE ROLE ADV_ANALYST_US;
USE SECONDARY ROLES NONE;

-- In Snowsight create a Streamlit app in ADV_ORDERS.CONSUMER using ADV_WH.
-- Paste Streamlit-Gold.py. Create it as ADV_ANALYST_US, NOT ADV_LAB.
-- The app is deliberately US-scoped for all its viewers; it is not per-viewer RBAC.
-- Confirm 2 active US orders / 165 and masked contact values.
-- App environment/creation is a separately rehearsed UI branch; core SQL works
-- without it. Do not share this training app externally as part of the lab.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Prepare a policy-independent aggregate for optional account sharing
-- ──────────────────────────────────────────────────────────────────────────────

USE ROLE ADV_LAB;

CREATE SECURE VIEW CONSUMER.SHARE_US_METRICS AS
SELECT REGION, ACTIVE_ORDERS, ACTIVE_AMOUNT_USD FROM GOLD.ORDER_METRICS_DT WHERE REGION = 'US';

SELECT * FROM CONSUMER.SHARE_US_METRICS;

-- CHECKPOINT: US / 2 / 165. This intentionally shares ONLY US aggregate values.
-- Current-role policies do not transfer transparently to every external consumer.
-- Optional-DataShare.sql supplies producer/consumer steps with a prevalidated
-- second account. Account identifiers must be provided and separately authorized.
-- Cross-account sharing is not proof of external-engine Iceberg interoperability.

USE ROLE ADV_LAB;
USE SECONDARY ROLES NONE;
