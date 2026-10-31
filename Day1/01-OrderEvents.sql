/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
1) Define the order-event contract
2) Create deterministic JSON fixtures using SQL
3) Unload files to an internal stage and verify their contents


-- The goal: prepare repeatable event data and establish the landing area for the ingestion pipeline.

Students should finish with:
- A known set of sample events.
- JSON files generated from those events in an internal stage.
- Verification that they can list the files and query their contents.
----------------------------------------------------------------------------------*/

-- 01 | Project contract and SQL-only fixture creation
-- Instructor runs each STEP; everyone repeats and checks before continuing.
-- Diagram: Pipeline-progression.md, Lab 01 - Fixture and staged files.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA BRONZE;

-- Use a common session time zone for classroom checks and LTZ history display.
-- This is session setup, not a conversion of stored event timestamps.
-- Fixture event_time strings already contain Z (UTC), so their TIMESTAMP_TZ
-- interpretation does not depend on this setting. Timestamps without an offset
-- would use the session zone when converted to TIMESTAMP_TZ.

ALTER SESSION SET TIMEZONE='UTC';


-- BUSINESS SCENARIO
-- Imagine an online retailer receiving purchase orders from customers.
-- The source order-management system sends a full snapshot whenever an order
-- is placed, revised, paid, or cancelled. We simulate those messages with SQL.
-- This is a simplified teaching model: no customer, item, tax, or payment detail.
-- All amounts are USD. Region is the order's business region, not a cloud region.
-- The downstream active-order total includes PLACED and PAID orders and excludes
-- CANCELLED orders. It is current active order value, not recognized revenue.


-- PAYLOAD CONTRACT: one JSON object describes one order-state event.
-- event_id   : Identity of an immutable message (for example, e4).
--              A repeated delivery keeps the same event_id and payload.
--              Different payloads for the same event_id are a conflict.
-- order_id   : Identity of the purchase order (for example, o1).
--              Several distinct events can describe changes to the same order.
-- version    : Positive integer revision of that order's business state.
--              The source system assigns it separately for each order.
--              Version 2 of o1 supersedes version 1 of o1, regardless of when
--              the messages reach Snowflake. Versions across orders are unrelated.
--              This is not a schema version, table version, or Snowflake metadata.
-- event_time : UTC time of the source business event, not its ingestion time.
-- status     : PLACED (submitted), PAID (payment recorded), or CANCELLED.
-- amount     : Full USD amount of the order at this revision, supplied as a string.
--              Silver converts and validates it; "oops" deliberately fails.
-- region     : US or EU; later used for aggregation and governed visibility.


-- EXAMPLE: o1 version 1 is PLACED for $100; version 2 is PAID for $120.
-- Imagine the customer changed the order before paying. The newer snapshot
-- replaces the earlier state: current amount is $120, not $100 + $120.
-- Each message is a complete snapshot, not a payment transaction or amount delta.
-- A cancellation remains as the latest state (a tombstone), so an old message
-- cannot make that order active again. Its retained amount is excluded from
-- the active-order total rather than deleted from the order history.


-- FIXTURE is controlled sample data, not the production ingestion destination.
-- batch selects the generated input file; it is outside the JSON payload.
-- payload stores the parsed JSON object as VARIANT. Only payload is unloaded.
-- The eight rows below form two four-row deliveries, not eight distinct orders.
-- Files may contain records in any order; precedence comes from the contract.

CREATE OR REPLACE TABLE FIXTURE
(
    batch NUMBER,
    payload VARIANT
);

INSERT INTO FIXTURE
SELECT column1, PARSE_JSON(column2)
FROM VALUES
-- Batch 1: initial purchase orders, an exact duplicate, and invalid source data.
-- e1: o1 is placed for $100 (version 1).
(1,'{"event_id":"e1","order_id":"o1","version":1,"event_time":"2026-11-02T09:00:00Z","status":"PLACED","amount":"100.00","region":"US"}'),
-- e2: o2 is placed for $50 in the EU (version 1).
(1,'{"event_id":"e2","order_id":"o2","version":1,"event_time":"2026-11-02T09:01:00Z","status":"PLACED","amount":"50.00","region":"EU"}'),
-- e2: duplicate delivery of the same immutable event; do not count it twice.
(1,'{"event_id":"e2","order_id":"o2","version":1,"event_time":"2026-11-02T09:01:00Z","status":"PLACED","amount":"50.00","region":"EU"}'),
-- e3: o3 has an invalid amount; retain the record with its rejection reason.
(1,'{"event_id":"e3","order_id":"o3","version":1,"event_time":"2026-11-02T09:02:00Z","status":"PLACED","amount":"oops","region":"US"}'),

-- Batch 2: newer states and one deliberately late, older state.
-- e4: o1 becomes PAID for $120 (version 2 replaces the earlier $100).
(2,'{"event_id":"e4","order_id":"o1","version":2,"event_time":"2026-11-02T10:00:00Z","status":"PAID","amount":"120.00","region":"US"}'),
-- e5: o2 is CANCELLED (version 2); retain its state, exclude its active value.
(2,'{"event_id":"e5","order_id":"o2","version":2,"event_time":"2026-11-02T10:01:00Z","status":"CANCELLED","amount":"50.00","region":"EU"}'),
-- e6: o3 has a valid newer snapshot for $30; e3 remains a rejected event.
(2,'{"event_id":"e6","order_id":"o3","version":2,"event_time":"2026-11-02T10:02:00Z","status":"PLACED","amount":"30.00","region":"US"}'),
-- e7: a delayed older snapshot of o1 ($90, version 1) arrives in batch 2.
-- It has a different event_id from e1, so it is not an exact-event duplicate.
-- It must not overwrite version 2. The fixture intentionally also exercises
-- equal-version precedence; Silver uses event_time, then event_id as a classroom
-- tie-breaker. A production source contract should reject ambiguous revisions.
(2,'{"event_id":"e7","order_id":"o1","version":1,"event_time":"2026-11-02T08:59:00Z","status":"PLACED","amount":"90.00","region":"US"}');

CREATE OR REPLACE FILE FORMAT EVENTS_JSON
    TYPE = JSON
    COMPRESSION = GZIP;

CREATE OR REPLACE STAGE EVENTS_STAGE
    FILE_FORMAT = EVENTS_JSON;

-- SQL unloading generates each participant's own files. No Python or shared bucket.
COPY INTO @EVENTS_STAGE/batch1/events.json.gz
FROM
(
    SELECT payload
    FROM FIXTURE
    WHERE batch = 1
)
SINGLE = TRUE
OVERWRITE = FALSE;

COPY INTO @EVENTS_STAGE/batch2/events.json.gz
FROM
(
    SELECT payload
    FROM FIXTURE
    WHERE batch = 2
)
SINGLE = TRUE
OVERWRITE = FALSE;


LIST @EVENTS_STAGE;

SELECT batch, COUNT(*)
FROM FIXTURE
GROUP BY batch
ORDER BY batch;

-- ──────────────────────────────────────────────────────────────────────────────
-- CHECKPOINT: 2 staged files; 4 fixture rows in each batch.
-- ──────────────────────────────────────────────────────────────────────────────
-- Do not rerun the unloads. Duplicate file paths and load metadata are separate
-- from duplicate business event IDs.

/* ----------------------------------------------------------------------------------

The intended responsibilities:

FIXTURE table:       Controlled sample data used to generate reproducible input batches.
EVENTS_JSON format:  JSON parsing and GZIP compression settings for the staged files.
EVENTS_STAGE:        Internal stage containing the two generated JSON files.


The result: two GZIP-compressed JSON files on the internal stage, generated
from four fixture rows per batch. LIST verifies that both files are present;
the fixture counts verify the number of input rows in each batch.
----------------------------------------------------------------------------------*/
