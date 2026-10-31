/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
1) Inspect Bronze input and define the Silver target tables
2) Develop each SELECT with real rows before creating its view
3) Run the processing statements individually and demonstrate ROLLBACK
4) Combine the verified steps into APPLY_EVENTS and commit the real result
5) Repeat execution and verify that the accepted state remains unchanged
----------------------------------------------------------------------------------*/

-- 03 | Develop, inspect, then make Silver processing reusable.

-- Diagram: Pipeline-progression.md, Lab 03 - Bronze to current Silver state.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA SILVER;

-- Run one statement or commented group at a time in the SAME worksheet/session.
-- Pause at each result. The first-pass checkpoints assume the eight raw rows
-- from Lab 02, an empty Silver inbox, and an unconsumed Bronze stream.
-- Tables use IF NOT EXISTS so rerunning setup preserves data and stream progress.
-- On a later rerun, compare with your starting counts; do not delete accepted data.
-- Views and the procedure use OR REPLACE to update reusable definitions.
-- No tasks should be processing this same inbox while we demonstrate transactions.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1: Inspect Bronze input and define the Silver destination.
-- ──────────────────────────────────────────────────────────────────────────────

-- Start with what we already have: immutable events delivered to Bronze.
-- Each payload is a full order state reported by the source transactional system.
-- The same event may arrive more than once; arrival order may differ from revision order.

SELECT payload, source_file, source_row, scan_time
FROM BRONZE.EVENTS_RAW
ORDER BY source_file, source_row;

-- Now define the known Silver tables before developing the transformation.
-- ORDERS_CURRENT is the output Gold will consume: one accepted current state
-- per order_id, with typed attributes and the event_id/version that established it.
-- Newer accepted states take precedence; a late older event must not overwrite them.
-- Keep CANCELLED orders in Silver so an older event cannot recreate an active order.
-- One row per order is enforced by our selection/MERGE logic, not a declared constraint.
-- EVENT_INBOX supports processing and investigation: retain every consumed delivery,
-- including duplicates and invalid payloads, together with its delivery lineage.
-- Views and the procedure will implement the path from Bronze to these tables.

-- The inbox is durable delivery history. Rejected data remains explainable.
-- LIKE gives it the same payload and lineage columns as the Bronze destination.

CREATE TABLE IF NOT EXISTS EVENT_INBOX LIKE BRONZE.EVENTS_RAW;

-- Define the current-order destination now; we will populate it in Step 5.

CREATE TABLE IF NOT EXISTS ORDERS_CURRENT
(
    order_id STRING,
    event_id STRING,
    version NUMBER,
    event_time TIMESTAMP_TZ,
    status STRING,
    amount NUMBER(12, 2),
    region STRING
);

SELECT COUNT(*) AS raw_rows
FROM BRONZE.EVENTS_RAW;

SELECT COUNT(*) AS inbox_rows
FROM EVENT_INBOX;

SELECT COUNT(*) AS current_orders
FROM ORDERS_CURRENT;

SELECT COUNT(*) AS pending_rows
FROM BRONZE.EVENTS_STREAM;

-- CHECKPOINT on the first pass: raw_rows = 8, inbox_rows = 0,
-- current_orders = 0, pending_rows = 8. The destination is defined, but not populated.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2: Try the typed SELECT with real input, then create the view.
-- ──────────────────────────────────────────────────────────────────────────────

-- Temporarily populate the inbox so the SELECT returns real event rows.
-- We will roll this INSERT back before creating the view.
-- DDL such as CREATE VIEW implicitly commits an open transaction in Snowflake.
-- Never execute DDL between this BEGIN TRANSACTION and its ROLLBACK.
-- Source: https://docs.snowflake.com/en/sql-reference/transactions

BEGIN TRANSACTION;

INSERT INTO SILVER.EVENT_INBOX (payload, source_file, source_row, scan_time)
SELECT payload, source_file, source_row, scan_time
FROM BRONZE.EVENTS_STREAM;

SELECT payload:event_id::STRING AS event_id, source_file
FROM EVENT_INBOX;

-- First inspect the conversion query itself. Safe conversions return NULL
-- for unsuitable values instead of making the whole query fail.
-- Expect eight deliveries, including two e2 rows. For e3, amount becomes NULL.
-- That is a conversion result to classify, rather than an empty dataset.

SELECT
    payload,
    source_file,
    source_row,
    scan_time,
    
    NULLIF(TRIM(payload:event_id::STRING),'') event_id,
    NULLIF(TRIM(payload:order_id::STRING),'') order_id,
    TRY_TO_DECIMAL(payload:version::STRING, 38, 9) version,
    TRY_TO_TIMESTAMP_TZ(payload:event_time::STRING) event_time,
    payload:status::STRING status,
    TRY_TO_DECIMAL(payload:amount::STRING, 12, 2) amount,
    payload:region::STRING region
FROM EVENT_INBOX;

-- Discuss the result before turning the query into a reusable view.
-- End the trial transaction first: inbox rows and stream progress do not commit.

ROLLBACK;

SELECT COUNT(*) AS inbox_rows
FROM EVENT_INBOX;

SELECT COUNT(*) AS pending_rows
FROM BRONZE.EVENTS_STREAM;

-- CHECKPOINT on the first pass: inbox_rows = 0, pending_rows = 8.

-- The view now stores the SELECT we have just inspected. It stores no rows.

CREATE OR REPLACE VIEW TYPED_EVENTS AS
SELECT
    payload,
    source_file,
    source_row,
    scan_time,
    
    NULLIF(TRIM(payload:event_id::STRING),'') event_id,
    NULLIF(TRIM(payload:order_id::STRING),'') order_id,
    TRY_TO_DECIMAL(payload:version::STRING, 38, 9) version,
    TRY_TO_TIMESTAMP_TZ(payload:event_time::STRING) event_time,
    payload:status::STRING status,
    TRY_TO_DECIMAL(payload:amount::STRING, 12, 2) amount,
    payload:region::STRING region
FROM EVENT_INBOX;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3: Try the classification SELECT, then create the view.
-- ──────────────────────────────────────────────────────────────────────────────

-- Populate the inbox again inside a new trial transaction.
-- The typed view reads these uncommitted rows in this same session.

BEGIN TRANSACTION;

INSERT INTO SILVER.EVENT_INBOX (payload, source_file, source_row, scan_time)
SELECT payload, source_file, source_row, scan_time
FROM BRONZE.EVENTS_STREAM;

SELECT event_id, version, amount
FROM TYPED_EVENTS
ORDER BY event_id;

-- The CASE expression applies the business contract to the typed values.
-- Expect e3 to have BAD_AMOUNT; the other seven deliveries have no rejection.
-- An identical duplicate is valid input here; latest-state selection comes later.

SELECT
    *,
    CASE
        WHEN event_id IS NULL OR order_id IS NULL THEN 'MISSING_KEY'
        WHEN version IS NULL OR version < 1 OR version <> TRUNC(version) THEN 'BAD_VERSION'
        WHEN event_time IS NULL THEN 'BAD_TIME'
        WHEN status IS NULL OR status NOT IN ('PLACED','PAID','CANCELLED') THEN 'BAD_STATUS'
        WHEN amount IS NULL OR amount < 0 THEN 'BAD_AMOUNT'
        WHEN region IS NULL OR region NOT IN ('US','EU') THEN 'BAD_REGION'
        ELSE NULL
    END AS reject_reason
FROM TYPED_EVENTS;

ROLLBACK;

-- The reviewed CASE query becomes the classification view, outside the transaction.

CREATE OR REPLACE VIEW CLASSIFIED_EVENTS AS
SELECT
    *,
    CASE
        WHEN event_id IS NULL OR order_id IS NULL THEN 'MISSING_KEY'
        WHEN version IS NULL OR version < 1 OR version <> TRUNC(version) THEN 'BAD_VERSION'
        WHEN event_time IS NULL THEN 'BAD_TIME'
        WHEN status IS NULL OR status NOT IN ('PLACED','PAID','CANCELLED') THEN 'BAD_STATUS'
        WHEN amount IS NULL OR amount < 0 THEN 'BAD_AMOUNT'
        WHEN region IS NULL OR region NOT IN ('US','EU') THEN 'BAD_REGION'
        ELSE NULL
    END AS reject_reason
FROM TYPED_EVENTS;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 4: Inspect rejected rows and immutable-event conflicts, then create views.
-- ──────────────────────────────────────────────────────────────────────────────

BEGIN TRANSACTION;

INSERT INTO SILVER.EVENT_INBOX (payload, source_file, source_row, scan_time)
SELECT payload, source_file, source_row, scan_time
FROM BRONZE.EVENTS_STREAM;

-- Start with a short inspection query: expect e3 / BAD_AMOUNT.

SELECT event_id, reject_reason
FROM CLASSIFIED_EVENTS
WHERE reject_reason IS NOT NULL;

-- Review the full-row filter we will reuse as REJECTED_EVENTS.

SELECT *
FROM CLASSIFIED_EVENTS
WHERE reject_reason IS NOT NULL;

-- Find conflicting reuse of an event_id, not ordinary duplicate deliveries.
-- event_id identifies ONE immutable business event. Re-delivering that same
-- event is allowed; changing its content while keeping its ID is not.
--
-- Example A: e2 / o2 / version 1 / amount 50 arrives twice, same full payload.
-- There are 2 deliveries but only 1 DISTINCT payload: no conflict is returned.
-- Example B: e2 / o2 / version 1 / amount 50 and the same e2 with amount 60.
-- There are 2 DISTINCT payloads for one ID: return e2 and stop processing.
-- Example C: o2 changes from version 1 to version 2 under a NEW event_id.
-- That is a normal state-change event, not a conflict with the earlier event.
--
-- WHERE: include only rows that passed the business validation rules.
-- Invalid rows remain in REJECTED_EVENTS and are not checked by this query.
-- GROUP BY: collect deliveries of the same event_id, not of the same order_id.
-- TO_JSON: represent each payload as text for this classroom comparison.
-- COUNT(DISTINCT ...): count different payload representations, not deliveries.
-- HAVING > 1: keep IDs whose valid deliveries disagree about event content.
-- File name, row number and scan time are outside payload and are not compared.
--
-- The fixture contains an identical e2 replay, so expect NO conflict rows.
-- Production limitation: TO_JSON does not guarantee JSON object key order.
-- A general implementation needs a defined canonical comparison of event content.
-- Source: https://docs.snowflake.com/en/sql-reference/functions/to_json

SELECT event_id
FROM CLASSIFIED_EVENTS
WHERE reject_reason IS NULL
GROUP BY event_id
HAVING COUNT(DISTINCT TO_JSON(payload)) > 1;

ROLLBACK;

-- Create each view only after checking its SELECT; there is no open transaction.

CREATE OR REPLACE VIEW REJECTED_EVENTS AS
SELECT *
FROM CLASSIFIED_EVENTS
WHERE reject_reason IS NOT NULL;

-- Reuse the conflict check reviewed above. This view lists conflicting event IDs;
-- it neither removes duplicates nor chooses which conflicting payload is correct.
-- APPLY_EVENTS checks this view and rolls back if any conflict is present.

CREATE OR REPLACE VIEW EVENT_CONFLICTS AS
SELECT event_id
FROM CLASSIFIED_EVENTS
WHERE reject_reason IS NULL
GROUP BY event_id
HAVING COUNT(DISTINCT TO_JSON(payload)) > 1;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 5: Run the processing statements manually, inspect the result, then roll back.
-- ──────────────────────────────────────────────────────────────────────────────

SELECT COUNT(*) AS inbox_rows
FROM EVENT_INBOX;

SELECT COUNT(*) AS current_orders
FROM ORDERS_CURRENT;

SELECT COUNT(*) AS pending_rows
FROM BRONZE.EVENTS_STREAM;

-- Record these baseline counts: 0 / 0 / 8 on the first pass.

BEGIN TRANSACTION;

INSERT INTO SILVER.EVENT_INBOX (payload, source_file, source_row, scan_time)
SELECT payload, source_file, source_row, scan_time
FROM BRONZE.EVENTS_STREAM;

SELECT COUNT(*) AS inbox_rows
FROM EVENT_INBOX;

-- Verify conflicts before making target changes: expect conflicts = 0.
-- If it is not zero, execute ROLLBACK and stop. Do not continue to MERGE.

SELECT COUNT(*) AS conflicts
FROM EVENT_CONFLICTS;

-- Inspect the candidate SELECT before embedding it in MERGE.
-- It chooses one valid latest state per order from the preserved inbox history.
-- Expect o1/e4/v2/PAID/120, o2/e5/v2/CANCELLED/50, o3/e6/v2/PLACED/30.
-- A lower-version late arrival cannot resurrect a cancelled order.
-- Equal versions use event_time then event_id as a documented classroom rule.
-- Production contracts should reject ambiguous versions instead of lexical ties.

SELECT order_id, event_id, version, event_time, status, amount, region
FROM CLASSIFIED_EVENTS
WHERE reject_reason IS NULL
QUALIFY ROW_NUMBER() OVER
(
    PARTITION BY order_id
    ORDER BY version DESC, event_time DESC, event_id DESC,
             source_file, source_row
) = 1;

-- Use those candidates in MERGE. A new order is inserted; a higher-priority
-- state updates the existing order. An older state cannot overwrite a newer one.
-- The small teaching implementation ranks inbox history.
-- Affected-order processing is a production extension.

MERGE INTO SILVER.ORDERS_CURRENT t
USING
(
    SELECT order_id, event_id, version, event_time, status, amount, region
    FROM SILVER.CLASSIFIED_EVENTS
    WHERE reject_reason IS NULL
    QUALIFY ROW_NUMBER() OVER
    (
        PARTITION BY order_id
        ORDER BY version DESC, event_time DESC, event_id DESC,
                 source_file, source_row
    ) = 1
) s
ON t.order_id = s.order_id

WHEN MATCHED AND
(
    s.version > t.version
    OR (s.version = t.version AND s.event_time > t.event_time)
    OR (s.version = t.version AND s.event_time = t.event_time
        AND s.event_id > t.event_id)
)
THEN UPDATE SET
    event_id = s.event_id,
    version = s.version,
    event_time = s.event_time,
    status = s.status,
    amount = s.amount,
    region = s.region

WHEN NOT MATCHED THEN
    INSERT (order_id, event_id, version, event_time, status, amount, region)
    VALUES (s.order_id, s.event_id, s.version, s.event_time,
            s.status, s.amount, s.region);

SELECT *
FROM ORDERS_CURRENT
ORDER BY order_id;

SELECT event_id, reject_reason
FROM REJECTED_EVENTS;

-- The three current rows and e3 / BAD_AMOUNT are visible inside this transaction.

-- Now undo the trial. ROLLBACK removes its inbox/target changes and leaves
-- the stream offset unchanged. Existing baseline data, if any, is preserved.

ROLLBACK;

SELECT COUNT(*) AS inbox_rows
FROM EVENT_INBOX;

SELECT COUNT(*) AS current_orders
FROM ORDERS_CURRENT;

SELECT COUNT(*) AS pending_rows
FROM BRONZE.EVENTS_STREAM;

-- CHECKPOINT: the three counts match the baseline recorded before BEGIN.
-- On the first pass: inbox_rows = 0, current_orders = 0, pending_rows = 8.
-- Deleting target rows after COMMIT would not rewind a consumed stream offset.
-- That is why this processing demonstration uses ROLLBACK rather than cleanup DELETE.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 6: Combine the verified steps into a reusable stored procedure.
-- ──────────────────────────────────────────────────────────────────────────────

-- We have inspected INSERT, conflict detection, candidate selection and MERGE.
-- The procedure combines the same processing steps with a conflict guard.
-- On success it COMMITs both the Silver writes and stream consumption.
-- On an exception it ROLLBACKs and re-raises the error.
-- Create the procedure outside any explicit transaction. It owns its transaction.
-- EXECUTE AS OWNER supplies the owner's privileges to the controlled operation.

CREATE OR REPLACE PROCEDURE APPLY_EVENTS()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    conflicts NUMBER;
    bad_event EXCEPTION (-20001, 'Conflicting payloads for immutable event_id');
BEGIN
    BEGIN TRANSACTION;

    -- Capture deliveries and consume the stream only if the transaction commits.
    INSERT INTO SILVER.EVENT_INBOX
    SELECT payload, source_file, source_row, scan_time
    FROM BRONZE.EVENTS_STREAM;

    SELECT COUNT(*) INTO :conflicts
    FROM SILVER.EVENT_CONFLICTS;

    IF (conflicts > 0) THEN
        RAISE bad_event;
    END IF;

    -- Rebuild candidates from the preserved inbox for this small teaching fixture.
    MERGE INTO SILVER.ORDERS_CURRENT t
    USING
    (
        SELECT order_id, event_id, version, event_time, status, amount, region
        FROM SILVER.CLASSIFIED_EVENTS
        WHERE reject_reason IS NULL
        QUALIFY ROW_NUMBER() OVER
        (
            PARTITION BY order_id
            ORDER BY version DESC, event_time DESC, event_id DESC,
                     source_file, source_row
        ) = 1
    ) s
    ON t.order_id = s.order_id

        WHEN MATCHED AND
    (
        s.version > t.version
        OR (s.version = t.version AND s.event_time > t.event_time)
        OR (s.version = t.version AND s.event_time = t.event_time
            AND s.event_id > t.event_id)
    )
    THEN UPDATE SET
        event_id = s.event_id,
        version = s.version,
        event_time = s.event_time,
        status = s.status,
        amount = s.amount,
        region = s.region

        WHEN NOT MATCHED THEN
        INSERT (order_id, event_id, version, event_time, status, amount, region)
        VALUES (s.order_id, s.event_id, s.version, s.event_time,
                s.status, s.amount, s.region);

    COMMIT;

    RETURN 'Applied';

EXCEPTION
        WHEN OTHER THEN
        ROLLBACK;

        RAISE;

END;
$$;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 7: Call the procedure, verify the committed result, then repeat.
-- ──────────────────────────────────────────────────────────────────────────────

CALL APPLY_EVENTS();

SELECT *
FROM ORDERS_CURRENT
ORDER BY order_id;

-- CHECKPOINT: o1/e4/v2/PAID/120; o2/e5/v2/CANCELLED/50; o3/e6/v2/PLACED/30.

SELECT event_id, reject_reason
FROM REJECTED_EVENTS;

SELECT COUNT(*) AS inbox_rows
FROM EVENT_INBOX;

SELECT COUNT(*) AS pending_rows
FROM BRONZE.EVENTS_STREAM;

-- CHECKPOINT on the first pass: e3 / BAD_AMOUNT; inbox_rows = 8; pending_rows = 0.

-- Call again with no new deliveries. The accepted state should remain unchanged.

CALL APPLY_EVENTS();

SELECT COUNT(*) AS inbox_rows
FROM EVENT_INBOX;

SELECT COUNT(*) AS current_orders
FROM ORDERS_CURRENT;

SELECT COUNT(*) AS pending_rows
FROM BRONZE.EVENTS_STREAM;

-- CHECKPOINT on the first pass: inbox_rows = 8, current_orders = 3, pending_rows = 0.
