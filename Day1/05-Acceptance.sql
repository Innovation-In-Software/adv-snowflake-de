/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright Â© 2026 Innovation In Software Corporation. All rights reserved.
1) State expected results and display matching pipeline rows with INTERSECT
2) Demonstrate rollback without stream consumption
3) Explain replay, cancellation and operational correctness
----------------------------------------------------------------------------------*/

-- 05 | Day 1 acceptance and handoff

-- Diagram: Pipeline-progression.md, Lab 05 - Acceptance and rollback evidence.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

-- ============================================================================
-- PART A: ACCEPTANCE - compare the completed pipeline with the expected state.
-- ============================================================================
-- Run after Lab 04 has completed both tasks successfully, and BEFORE Lab 06.
-- Expected delivery counts: EVENTS_RAW = 10, EVENT_INBOX = 10.
-- Expected current orders (exactly 3 rows):
-- order_id | event_id | version | event_time (UTC)      | status    | amount | region
-- o1       | e4       | 2       | 2026-11-02 10:00:00   | PAID      | 120    | US
-- o2       | e5       | 2       | 2026-11-02 10:01:00   | CANCELLED | 50     | EU
-- o3       | e8       | 3       | 2026-11-02 11:00:00   | PAID      | 45     | US
-- Expected Gold (exactly 1 row): US / active_orders 2 / active_amount_usd 165.
-- Expected rejected event (exactly 1 row): e3 / BAD_AMOUNT.
-- Expected pending stream rows = 0; conflicting event IDs = 0.
-- Cancellation remains in current state, but contributes nothing to active Gold.

-- STEP A1: show expected and actual control totals side by side.
-- Every row must say PASS. A matching INTERSECT alone would not reveal extra
-- actual rows: these total-row checks also detect extra or duplicate rows.

WITH expected AS
(
    SELECT column1 AS check_name, column2 AS expected_value
    FROM VALUES
        ('Bronze rows', 10),
        ('Inbox rows', 10),
        ('Current orders', 3),
        ('Rejects', 1),
        ('Stream drained', 0),
        ('No conflicts', 0),
        ('Gold rows', 1),
        ('Gold value', 165)
),
actual AS
(
    SELECT 'Bronze rows' AS check_name, COUNT(*) AS actual_value
    FROM BRONZE.EVENTS_RAW
    UNION ALL
    SELECT 'Inbox rows', COUNT(*)
    FROM SILVER.EVENT_INBOX
    UNION ALL
    SELECT 'Current orders', COUNT(*)
    FROM SILVER.ORDERS_CURRENT
    UNION ALL
    SELECT 'Rejects', COUNT(*)
    FROM SILVER.REJECTED_EVENTS
    UNION ALL
    SELECT 'Stream drained', COUNT(*)
    FROM BRONZE.EVENTS_STREAM
    UNION ALL
    SELECT 'No conflicts', COUNT(*)
    FROM SILVER.EVENT_CONFLICTS
    UNION ALL
    SELECT 'Gold rows', COUNT(*)
    FROM GOLD.ORDER_METRICS
    UNION ALL
    SELECT 'Gold value', SUM(active_amount_usd)
    FROM GOLD.ORDER_METRICS
)
SELECT e.check_name, e.expected_value, a.actual_value,
       IFF(a.actual_value = e.expected_value, 'PASS', 'FAIL') AS result
FROM expected e
JOIN actual a ON a.check_name = e.check_name
ORDER BY e.check_name;

-- STEP A2: show the current-order rows that exactly match the expected state.
-- INTERSECT returns distinct rows present in BOTH inputs. Expect all 3 rows
-- listed above, including event time and region. Fewer rows means a mismatch.
-- Accept this result only together with A1: actual current-order count = 3.

WITH expected AS
(
    SELECT column1 AS order_id, column2 AS event_id, column3 AS version,
           TO_TIMESTAMP_TZ(column4) AS event_time, column5 AS status,
           column6 AS amount, column7 AS region
    FROM VALUES
        ('o1', 'e4', 2, '2026-11-02T10:00:00Z', 'PAID', 120, 'US'),
        ('o2', 'e5', 2, '2026-11-02T10:01:00Z', 'CANCELLED', 50, 'EU'),
        ('o3', 'e8', 3, '2026-11-02T11:00:00Z', 'PAID', 45, 'US')
)
SELECT order_id, event_id, version, event_time, status, amount, region
FROM SILVER.ORDERS_CURRENT
INTERSECT
SELECT order_id, event_id, version, event_time, status, amount, region
FROM expected
ORDER BY order_id;

-- STEP A3: show the matching Gold row. Expect exactly US / 2 / 165.
-- A1 must also report Gold rows = 1; cancelled EU orders produce no Gold row.

WITH expected AS
(
    SELECT column1 AS region, column2 AS active_orders, column3 AS active_amount_usd
    FROM VALUES ('US', 2, 165)
)
SELECT region, active_orders, active_amount_usd
FROM GOLD.ORDER_METRICS
INTERSECT
SELECT region, active_orders, active_amount_usd
FROM expected;

-- STEP A4: show the matching rejection. Expect exactly e3 / BAD_AMOUNT.
-- A later valid o3 event does not erase the original bad delivery.
-- A1 must also report Rejects = 1. Save results and query IDs for A1-A4.

WITH expected AS
(
    SELECT column1 AS event_id, column2 AS reject_reason
    FROM VALUES ('e3', 'BAD_AMOUNT')
)
SELECT event_id, reject_reason
FROM SILVER.REJECTED_EVENTS
INTERSECT
SELECT event_id, reject_reason
FROM expected;

-- ACCEPTANCE CHECKPOINT: 8 PASS controls; 3 matching current-order rows;
-- 1 matching Gold row; 1 matching rejected-event row. All are required.

-- ============================================================================
-- PART B: HELPER DEMONSTRATION - ROLLBACK preserves stream availability.
-- ============================================================================
-- This is a separate exercise, not another stage of the order pipeline.
-- Create its disposable objects HERE, immediately before the demonstration.
-- OR REPLACE resets only these demonstration objects when rerun in this session.
-- Never run this DDL inside the trial transaction below.

CREATE OR REPLACE TEMP TABLE STREAM_DEMO
(
    id NUMBER
);

CREATE OR REPLACE TEMP TABLE STREAM_DEMO_SINK
(
    id NUMBER
);

CREATE OR REPLACE STREAM STREAM_DEMO_CHANGES
ON TABLE STREAM_DEMO
APPEND_ONLY = TRUE;

INSERT INTO STREAM_DEMO VALUES (1);

BEGIN TRANSACTION;

INSERT INTO STREAM_DEMO_SINK
SELECT id
FROM STREAM_DEMO_CHANGES;

-- Inside this transaction, the sink contains the inserted row.

SELECT id
FROM STREAM_DEMO_SINK;

ROLLBACK;

-- After rollback: pending_rows = 1, sink_rows = 0.
-- The stream offset did not advance; the source row remains unchanged.

SELECT COUNT(*) AS pending_rows
FROM STREAM_DEMO_CHANGES;

SELECT COUNT(*) AS sink_rows
FROM STREAM_DEMO_SINK;

DROP STREAM IF EXISTS STREAM_DEMO_CHANGES;

-- Written exit check: why does file replay differ from business duplication?
-- Why retain CANCELLED rows? Why does scheduling success not prove correctness?
