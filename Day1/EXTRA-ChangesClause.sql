/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
1) Query a fixed interval of change-tracking metadata with CHANGES
2) Compare DEFAULT net changes with APPEND_ONLY inserts
3) Contrast repeatable CHANGES queries with committed stream consumption
----------------------------------------------------------------------------------*/

-- EXTRA | Day 1 | The CHANGES clause (allow approximately 15 minutes)
-- Run after Lab 05 and before Lab 06, in ONE worksheet/session throughout.
-- Disposable OPS objects keep this example separate from the order pipeline.
-- Rerun from STEP 1 to reset only this demonstration.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';
ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY1';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Create the disposable source and establish its initial state
-- ──────────────────────────────────────────────────────────────────────────────
-- CHANGES does not require a stream. Enable tracking explicitly before the
-- interval we intend to inspect; a stream is added only for comparison.
CREATE OR REPLACE TABLE OPS.CHANGES_DEMO
(
    order_id VARCHAR(10),
    status   VARCHAR(20),
    amount   NUMBER(10, 2)
)
CHANGE_TRACKING = TRUE;

INSERT INTO OPS.CHANGES_DEMO 
VALUES
    ('o1', 'NEW', 120.00),
    ('o2', 'NEW', 250.00),
    ('o3', 'NEW',  80.00);

-- Create AFTER the initial load but BEFORE the changes.
-- A new stream does not return existing table rows by default.
CREATE OR REPLACE STREAM OPS.CHANGES_DEMO_STREAM ON TABLE OPS.CHANGES_DEMO;

-- The sink records change rows, including their action; it is not current state.
CREATE OR REPLACE TABLE OPS.CHANGES_DEMO_SINK
(
    order_id      VARCHAR(10),
    status        VARCHAR(20),
    amount        NUMBER(10, 2),
    change_action VARCHAR(6),
    is_update     BOOLEAN
);

SET changes_start = CURRENT_TIMESTAMP();

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Make three kinds of change and close the observation interval
-- ──────────────────────────────────────────────────────────────────────────────
UPDATE OPS.CHANGES_DEMO
SET status = 'SHIPPED', amount = 135.00
WHERE order_id = 'o1';

DELETE FROM OPS.CHANGES_DEMO WHERE order_id = 'o2';
INSERT INTO OPS.CHANGES_DEMO VALUES ('o4', 'NEW', 410.00);

SET changes_end = CURRENT_TIMESTAMP();

SELECT * 
FROM OPS.CHANGES_DEMO 
ORDER BY order_id;

-- CHECKPOINT current state: o1/SHIPPED/135, o3/NEW/80, o4/NEW/410.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Read DEFAULT changes twice over exactly the same interval
-- ──────────────────────────────────────────────────────────────────────────────
-- DEFAULT returns the NET row-level delta, not every intermediate DML operation.
-- An insert followed by a delete within the interval cancels out, for example.
-- Our initial load is outside the interval, so the o1 update appears as a pair.
-- Fixed timestamps make repeated queries comparable. OFFSET => -300 moves with
-- the clock and can point before this table or its tracking metadata existed.

SELECT order_id, status, amount, METADATA$ACTION, METADATA$ISUPDATE, METADATA$ROW_ID
FROM OPS.CHANGES_DEMO
    CHANGES (INFORMATION => DEFAULT)
    AT (TIMESTAMP => $changes_start)
    END (TIMESTAMP => $changes_end)
ORDER BY order_id, METADATA$ACTION;

-- Run the SELECT above a second time. Expect these same FOUR change rows:
-- order_id | status  | amount | action | is_update
-- o1       | NEW     | 120    | DELETE | TRUE
-- o1       | SHIPPED | 135    | INSERT | TRUE
-- o2       | NEW     | 250    | DELETE | FALSE
-- o4       | NEW     | 410    | INSERT | FALSE
-- o3 did not change. Reading CHANGES does not consume anything.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 4 │ Read only appended rows over that interval
-- ──────────────────────────────────────────────────────────────────────────────
SELECT order_id, status, amount, METADATA$ACTION
FROM OPS.CHANGES_DEMO
    CHANGES (INFORMATION => APPEND_ONLY)
    AT (TIMESTAMP => $changes_start)
    END (TIMESTAMP => $changes_end);

-- CHECKPOINT: one row, o4 / NEW / 410 / INSERT.
-- APPEND_ONLY ignores updates and deletes; use it when only inserts matter.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 5 │ Consume the stream, then repeat the CHANGES query
-- ──────────────────────────────────────────────────────────────────────────────
-- SELECT alone does not consume a stream either. Its offset advances when a
-- transaction containing consuming DML commits. Make that boundary explicit.
SELECT COUNT(*) AS stream_rows_before_consumption
FROM OPS.CHANGES_DEMO_STREAM; -- 4

BEGIN TRANSACTION;

INSERT INTO OPS.CHANGES_DEMO_SINK (order_id, status, amount, change_action, is_update)
SELECT order_id, status, amount, METADATA$ACTION, METADATA$ISUPDATE
FROM OPS.CHANGES_DEMO_STREAM;

COMMIT;

SELECT COUNT(*) AS sink_change_rows 
FROM OPS.CHANGES_DEMO_SINK; -- 4

SELECT COUNT(*) AS stream_rows_after_consumption
FROM OPS.CHANGES_DEMO_STREAM; -- 0

SELECT order_id, status, amount, METADATA$ACTION, METADATA$ISUPDATE
FROM OPS.CHANGES_DEMO
    CHANGES (INFORMATION => DEFAULT)
    AT (TIMESTAMP => $changes_start)
    END (TIMESTAMP => $changes_end)
ORDER BY order_id, METADATA$ACTION;

-- CHECKPOINT: CHANGES still returns the same four rows. The stream's offset
-- advanced; these explicitly supplied CHANGES boundaries did not move.
-- Repeating STEP 5 inserts zero rows when there have been no further changes.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 6 │ Clean up the demonstration and verify the pipeline handoff
-- ──────────────────────────────────────────────────────────────────────────────
DROP STREAM IF EXISTS OPS.CHANGES_DEMO_STREAM;
DROP TABLE IF EXISTS OPS.CHANGES_DEMO_SINK;
DROP TABLE IF EXISTS OPS.CHANGES_DEMO;

UNSET (changes_start, changes_end);

-- ACCEPTANCE: DEFAULT=4 on repeated reads; APPEND_ONLY=1; sink=4; stream=0
-- after committed consumption; DEFAULT still=4 before cleanup.
-- Re-run Lab 05 acceptance: raw/inbox=14/14, current orders=3, Gold=US/2/165.
-- If Lab 06 has already added its replay, raw/inbox=15/15 instead; this extra
-- lab does not change either pipeline baseline.
-- History must still be retained AND change tracking must cover the interval.
-- CHANGES is not a permanent audit log or an automatically saved cursor.
-- Sources:
-- https://docs.snowflake.com/en/sql-reference/constructs/changes
-- https://docs.snowflake.com/en/sql-reference/sql/create-stream
