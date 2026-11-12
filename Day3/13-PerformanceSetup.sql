/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
C10 setup — deterministic scale without external data
1) Build the same repeatable performance fixture in every environment
2) Keep performance experiments separate from course business tables
3) Record exact scale and configuration before measurement
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 13 - Independent performance sandbox.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Create a bounded performance sandbox
-- ──────────────────────────────────────────────────────────────────────────────

-- Native SQL generator avoids sample-database availability and local Python.
-- The validated Day 3 scale is 50 million rows. In the 2026-11-09 rehearsal,
-- the ORDER_DATE comparison pruned to 1 of 16 partitions on X-Small.

CREATE SCHEMA PERF;

CREATE TABLE PERF.ORDERS_BASE AS
WITH NUMBERS AS
(
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS N
    FROM TABLE(GENERATOR(ROWCOUNT => 50000000))
)
SELECT N + 1 AS ORDER_ID,
       MOD(N * 7919, 100000) + 1 AS CUSTOMER_ID,
       DATEADD('day', MOD(N * 37, 730), '2024-01-01'::DATE) AS ORDER_DATE,
       IFF(MOD(N, 7) = 0, 'CANCELLED', 'PAID') AS STATUS,
       ((MOD(N * 97, 50000) + 1000) / 100)::NUMBER(12, 2) AS AMOUNT
FROM NUMBERS;

CREATE TABLE PERF.CUSTOMERS AS
WITH NUMBERS AS
(
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS CUSTOMER_ID
    FROM TABLE(GENERATOR(ROWCOUNT => 100000))
)
SELECT CUSTOMER_ID,
       CASE MOD(CUSTOMER_ID, 3) WHEN 0 THEN 'EU' WHEN 1 THEN 'US' ELSE 'APAC' END AS REGION
FROM NUMBERS;

CREATE TABLE PERF.MEASUREMENTS
(
    CASE_NAME   STRING,
    QUERY_ID    STRING,
    RECORDED_AT TIMESTAMP_LTZ
);

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Verify scale and configuration
-- ──────────────────────────────────────────────────────────────────────────────

SELECT COUNT(*) AS ROW_COUNT, COUNT(DISTINCT ORDER_ID) AS UNIQUE_ORDERS,
       MIN(ORDER_ID) AS FIRST_ORDER, MAX(ORDER_ID) AS LAST_ORDER
FROM PERF.ORDERS_BASE;

-- CHECKPOINT: 50000000 rows / 50000000 unique; IDs 1 through 50000000.

SELECT COUNT(*) AS CUSTOMERS FROM PERF.CUSTOMERS; -- 100000

SELECT COUNT(*) AS CUSTOMER_42_ORDERS FROM PERF.ORDERS_BASE WHERE CUSTOMER_ID = 42; -- 500

SHOW WAREHOUSES LIKE 'ADV_WH';

