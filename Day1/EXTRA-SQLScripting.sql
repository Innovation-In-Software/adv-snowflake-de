USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;
USE WAREHOUSE ADV_WH;

-- ──────────────────────────────────────────────────────────────────────────────
-- Step 1 (5 min) — An anonymous block: LET, IF, RETURN.
-- An anonymous block is not stored: it runs once and is discarded. It is the
-- fastest way to test scripting logic before wrapping it in a procedure.
-- ──────────────────────────────────────────────────────────────────────────────

BEGIN
    LET amount NUMBER(10,2) := 3200.00;
    LET band STRING;
    IF (amount >= 3000) THEN
        band := 'HIGH';
    ELSEIF (amount >= 1500) THEN
        band := 'MEDIUM';
    ELSE
        band := 'LOW';
    END IF;
    RETURN band;
END;
-- Expected: 'HIGH'. Change 3200.00 to 800.00 and re-run: 'LOW'.

-- ──────────────────────────────────────────────────────────────────────────────
-- Step 2 (10 min) — A stored procedure with exception handling: safe_divide.
-- A procedure is stored and called by name with CALL. Its body is SQL Scripting,
-- not JavaScript: LANGUAGE SQL, DECLARE for variables, EXCEPTION / WHEN OTHER
-- for the catch. Compare with Step 1: same IF logic, now reusable.
-- ──────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE OPS.SAFE_DIVIDE(a FLOAT, b FLOAT)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
    LET result FLOAT;
    BEGIN
        result := a / b;
    EXCEPTION
        WHEN OTHER THEN
            RETURN 'Error: cannot divide by zero';
    END;
    RETURN 'Result is ' || result;
END;
$$;

CALL OPS.SAFE_DIVIDE(10, 2);   -- Expected: 'Result is 5'
CALL OPS.SAFE_DIVIDE(10, 0);   -- Expected: 'Error: cannot divide by zero'

-- EXECUTE AS OWNER in one line: the procedure runs with its owner's privileges,
-- not the caller's. That is why Lab 03's SP_APPLY_EVENTS can write to SILVER
-- when a task calls it — the task runs as the procedure's owner. (The risks of
-- owner execution — input smuggling, non-atomic failure — are deck slide 62.)

-- ──────────────────────────────────────────────────────────────────────────────
-- Step 3 (10 min) — The Lab 03 pattern in miniature: a transaction that either
-- commits or rolls back, guarded by a conflict check.
-- This is SP_APPLY_EVENTS with the pipeline taken out: an INSERT, a conflict
-- check, a custom exception, COMMIT on success, ROLLBACK + re-raise on failure.
-- ──────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE OPS.BRIDGE_DEMO (
  order_id VARCHAR(10),
  amount   NUMBER(10,2)
);

INSERT INTO OPS.BRIDGE_DEMO VALUES ('o1', 120.00);

CREATE OR REPLACE PROCEDURE OPS.SP_BRIDGE_APPLY(p_order_id VARCHAR, p_amount NUMBER)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    existing NUMBER;
    duplicate_order EXCEPTION (-20001, 'Order already exists in BRIDGE_DEMO');
BEGIN
    BEGIN TRANSACTION;

    SELECT COUNT(*) INTO :existing
      FROM OPS.BRIDGE_DEMO
     WHERE order_id = :p_order_id;

    IF (existing > 0) THEN
        RAISE duplicate_order;
    END IF;

    INSERT INTO OPS.BRIDGE_DEMO VALUES (:p_order_id, :p_amount);

    COMMIT;
    RETURN 'Applied';

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

-- Good row: commits.
CALL OPS.SP_BRIDGE_APPLY('o2', 250.00);   -- Expected: 'Applied'
SELECT * FROM OPS.BRIDGE_DEMO ORDER BY order_id;  -- Expected: o1, o2.

-- Conflicting row: the exception fires, the transaction rolls back, nothing changes.
CALL OPS.SP_BRIDGE_APPLY('o1', 999.00);   -- Expected: error -20001, 'Order already exists in BRIDGE_DEMO'
SELECT * FROM OPS.BRIDGE_DEMO ORDER BY order_id;  -- Expected: still only o1, o2. The 999.00 row is not there.

-- Now read Lab 03's SP_APPLY_EVENTS with this in hand and name each part:
-- DECLARE + custom exception, BEGIN TRANSACTION, the conflict check + RAISE,
-- the MERGE in place of our INSERT, COMMIT, EXCEPTION WHEN OTHER + ROLLBACK + RAISE.
-- It is the same procedure, with the pipeline inside it.

-- ──────────────────────────────────────────────────────────────────────────────
-- Cleanup — drop only the bridge objects. Never touch BRONZE / SILVER / GOLD.
-- ──────────────────────────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS OPS.SP_BRIDGE_APPLY(VARCHAR, NUMBER);
DROP PROCEDURE IF EXISTS OPS.SAFE_DIVIDE(FLOAT, FLOAT);
DROP TABLE IF EXISTS OPS.BRIDGE_DEMO;

-- Acceptance (all must hold):
--   Step 1 returns 'HIGH' for 3200.00 and 'LOW' for 800.00.
--   Step 2: CALL SAFE_DIVIDE(10, 2) returns 'Result is 5'; CALL SAFE_DIVIDE(10, 0)
--           returns 'Error: cannot divide by zero'.
--   Step 3: after the good call, BRIDGE_DEMO holds o1 and o2; after the conflicting
--           call, it still holds only o1 and o2 (no 999.00 row), and the call raises
--           error -20001.
--   Pipeline untouched: BRONZE / SILVER / GOLD are never referenced in this lab.
-- Teaching notes:
--   - If the room is strong on scripting, cut Step 1 to a 2-minute demo and keep
--     Steps 2 and 3 (15 min total). If the room is weak, keep all three (30 min)
--     and pay for it from slide time, never from a core lab.
--   - The one idea to land before Lab 03: a procedure owns its transaction.
--     That is why Lab 03 says "create the procedure outside any explicit
--     transaction" — the procedure begins and commits (or rolls back) its own.
