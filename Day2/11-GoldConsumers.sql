/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
-— Consume governed Gold without widening access
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
FROM CONSUMER.VW_ORDERS
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
-- STEP 3 │ Run the same Streamlit app locally
-- ──────────────────────────────────────────────────────────────────────────────

-- The same Streamlit-Gold.py can run on your workstation instead of in
-- Snowsight. It still queries the governed Snowflake consumer view.
--
-- Before starting, complete the local key-pair setup. In the repository-root
-- .env, set SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER and SNOWFLAKE_PRIVATE_KEY_FILE.
-- If the private key is encrypted, also set SNOWFLAKE_PRIVATE_KEY_FILE_PWD.
-- The user must have the ADV_ANALYST_US role and its public key registered.
-- Keep the private key and .env private; do not commit them.
--
-- From a PowerShell terminal at the repository root, not a SQL worksheet:
--
-- python -m pip install -r Day2\requirements-local.txt
-- python -m streamlit run Day2\Streamlit-Gold.py -- --local
--
-- Install dependencies once; use --local to select the key-pair connection.
-- Streamlit may ask for an optional email on first launch: press Enter to skip.
-- Open the local URL printed in the terminal. Stop the app with Ctrl+C.
--
-- Locally, the app connects as ADV_ANALYST_US, disables secondary roles, and
-- uses ADV_WH and ADV_ORDERS.CONSUMER. Unlike the hosted app, the connection
-- uses your local user's credentials; it does not authenticate browser viewers.
-- CHECKPOINT: at the default slider value, two active US orders total 165 USD
-- and emails are masked. Set the minimum to 50: one order totals 120 USD.
-- Moving the slider filters the already-authorized rows.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 4 │ Optional: inspect governed Gold in a notebook
-- ──────────────────────────────────────────────────────────────────────────────

-- Governed-Gold.ipynb explores the same consumer contract and the distinction
-- between authorization and Dynamic Table freshness. Its Snowsight UI import
-- path is an unrehearsed template / discussion-only, not a required hands-on step.
-- If the instructor demonstrates it, import the notebook into
-- ADV_ORDERS.CONSUMER as ADV_ANALYST_US, select ADV_WH as the query warehouse
-- and use the Snowflake warehouse Python runtime. Run its cells in order.
--
-- CHECKPOINT: the role guard confirms ADV_ANALYST_US; the view returns US orders
-- o1 and o3 with masked emails; two active orders total 165 USD.
-- A successful consumer query does not prove upstream freshness: ask the
-- engineer to inspect refresh evidence rather than granting Silver access.
