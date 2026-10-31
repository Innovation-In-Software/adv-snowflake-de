/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
D1 — Optional prevalidated Iceberg observation
1) Inspect the prepared Snowflake-managed Iceberg object
2) Record table and snapshot evidence before external access
3) Compare a REST-catalog client against the same snapshot
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 12 - Optional Iceberg interoperability.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY2';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Inspect available storage/catalog prerequisites
-- ──────────────────────────────────────────────────────────────────────────────

-- This optional branch is gated. It does not create credentials or cloud storage.
-- Every participant reproducing it needs the SAME validated preparation path.

SHOW EXTERNAL VOLUMES;

SHOW ICEBERG TABLES IN DATABASE ADV_ORDERS;

-- If no prepared table/volume is available, mark BLOCKED and use the discussion
-- in Optional-Iceberg-DuckDB.md. The core Day 2 sequence is unaffected.

-- Adapt and uncomment only after the exact table name is frozen in rehearsal:
-- SELECT GET_DDL('TABLE', 'ADV_ORDERS.GOLD.ORDERS_ICEBERG');
-- SELECT COUNT(*) AS ROWS, SUM(AMOUNT) AS TOTAL_ORDER_AMOUNT
-- FROM ADV_ORDERS.GOLD.ORDERS_ICEBERG;
-- SELECT SYSTEM$GET_ICEBERG_TABLE_INFORMATION('ADV_ORDERS.GOLD.ORDERS_ICEBERG');

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Record interoperability proof, not a different copy of the data
-- ──────────────────────────────────────────────────────────────────────────────

-- Required evidence: catalog endpoint/client version, table identity, snapshot ID,
-- schema and decimal semantics, row count, ORDER_ID set, and amount total.
-- Pause writes or pin the snapshot while comparing. A shared Snowflake database
-- or exported Parquet copy is not the same interoperability demonstration.
-- External writes remain out of scope until the exact client path is tested.
