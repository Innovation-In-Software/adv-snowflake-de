/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
1) Use variables and conditional logic in an anonymous scripting block
2) Create a reusable SQL procedure and inspect handled exceptions
3) Commit valid writes and roll back conflicting writes before re-raising an error
4) Compare a nested SQL procedure with anonymous Python procedures
----------------------------------------------------------------------------------*/

-- Lab 06 | Day 1 | SQL scripting bridge (allow approximately 30 minutes)
-- Run after environment setup and before Lab 07, one complete block at a time.
-- STEPS 3 and 4 deliberately raise errors: inspect them, then continue checking.
-- Run CREATE and CALL statements outside any caller-started transaction.
-- Rerun from STEP 1 to reset only these disposable OPS demonstration objects.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';
ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY1';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Use LET, IF and RETURN in an anonymous block (5 minutes)
-- An anonymous block is not stored: it runs once and is discarded. It is the
-- fastest way to test scripting logic before wrapping it in a procedure.
-- ──────────────────────────────────────────────────────────────────────────────

-- EXECUTE IMMEDIATE keeps the block together in worksheets and SQL clients.
-- BEGIN ... END defines a scripting block; BEGIN TRANSACTION starts a transaction.
EXECUTE IMMEDIATE $$
BEGIN
    LET amount NUMBER(10, 2) := 3200.00;
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
$$;
-- CHECKPOINT: HIGH. Change 3200.00 to 800.00 and re-run: LOW.
-- Try 2000.00 as well: MEDIUM.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Create a procedure with exception handling (10 minutes)
-- A procedure is stored and called by name with CALL.
-- LANGUAGE SQL selects Snowflake Scripting. Here LET declares a local variable;
-- STEP 3 uses DECLARE for variables and a named exception.
-- ──────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE OPS.SP_SAFE_DIVIDE(a FLOAT, b FLOAT)
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
            RETURN 'Error: ' || SQLERRM;
    END;
    RETURN 'Result is ' || result;
END;
$$;

CALL OPS.SP_SAFE_DIVIDE(10, 2); -- CHECKPOINT: Result is 5
CALL OPS.SP_SAFE_DIVIDE(10, 0); -- CHECKPOINT: Error: Division by zero
-- WHEN OTHER catches any exception in the inner block. SQLERRM preserves the
-- actual cause instead of mislabeling every possible error as division by zero.
-- This handled error returns text: CALL succeeds. STEP 3 re-raises instead,
-- so its caller receives a failure. These are different error contracts.

-- EXECUTE AS OWNER in one line: the procedure runs with its owner's privileges,
-- not the caller's. That is why Lab 07's SP_APPLY_EVENTS can write to SILVER
-- when called by a role authorized to execute the procedure. A task itself
-- normally runs with its TASK owner's privileges; the procedure's EXECUTE AS
-- setting determines the privileges inside the procedure. Both owners happen
-- to be ADV_LAB in our pipeline. Owner rights do not make multiple writes atomic.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Commit a valid write or roll back a conflict (10 minutes)
-- A transaction commits or rolls back, guarded by a conflict check.
-- This illustrates the SP_APPLY_EVENTS pattern: an INSERT, a conflict
-- check, a custom exception, COMMIT on success, ROLLBACK + re-raise on failure.
-- ──────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE OPS.BRIDGE_DEMO
(
    order_id VARCHAR(10),
    amount   NUMBER(10, 2)
);

INSERT INTO OPS.BRIDGE_DEMO VALUES ('o1', 120.00);

CREATE OR REPLACE PROCEDURE OPS.SP_BRIDGE_APPLY(p_order_id VARCHAR, p_amount NUMBER)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    matching_orders NUMBER;
    duplicate_order EXCEPTION (-20001, 'Order already exists in BRIDGE_DEMO');
BEGIN
    BEGIN TRANSACTION;

    -- Write first so the failing call demonstrates undoing an actual INSERT.
    -- Inside SQL statements, : binds a scripting variable or argument.
    -- Scripting expressions such as IF below use variable names without :.
    INSERT INTO OPS.BRIDGE_DEMO VALUES (:p_order_id, :p_amount);

    SELECT COUNT(*) INTO :matching_orders
    FROM OPS.BRIDGE_DEMO
    WHERE order_id = :p_order_id;

    IF (matching_orders > 1) THEN
        RAISE duplicate_order;
    END IF;

    COMMIT;
    RETURN 'Applied';

EXCEPTION
    WHEN OTHER THEN
        -- Close this procedure's transaction explicitly, then propagate the error.
        -- Without ROLLBACK, an escaping RAISE would still leave an unfinished
        -- procedure-scoped transaction, which Snowflake rolls back on exit.
        -- An exception caught inside the procedure does not itself end a transaction.
        ROLLBACK;
        RAISE;
END;
$$;

-- Good row: commits.
CALL OPS.SP_BRIDGE_APPLY('o2', 250.00);   -- Expected: 'Applied'
SELECT * FROM OPS.BRIDGE_DEMO ORDER BY order_id;  -- Expected: o1, o2.

-- Conflicting row: the exception fires, the transaction rolls back, nothing changes.
-- Run this CALL separately. Its deliberate error is a successful negative test;
-- continue with the SELECT below even if your client stops executing on errors.
CALL OPS.SP_BRIDGE_APPLY('o1', 999.00);   -- Expected: error -20001, 'Order already exists in BRIDGE_DEMO'
SELECT * FROM OPS.BRIDGE_DEMO ORDER BY order_id;  -- Expected: still only o1, o2. The 999.00 row is not there.

-- Now read Lab 07's SP_APPLY_EVENTS with this in hand and name each part:
-- DECLARE + custom exception, BEGIN TRANSACTION, the conflict check + RAISE,
-- the MERGE in place of our INSERT, COMMIT, EXCEPTION WHEN OTHER + ROLLBACK + RAISE.
-- It uses the same transaction/error-handling pattern, not the same business rule.
-- Lab 07 checks conflicting event payloads; this miniature checks duplicate orders.
-- This count-based example is for one classroom session, not a concurrency-safe
-- uniqueness constraint. The explicit transaction provides rollback, not uniqueness.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 4 │ Observe a normal RETURN with an unfinished transaction (5 minutes)
-- ──────────────────────────────────────────────────────────────────────────────
-- Deliberately incomplete transaction handling. There is no RAISE in this body.
-- Unlike a client that commits on normal disconnect, returning from a Snowflake
-- procedure does not commit a transaction that the procedure started.
CREATE OR REPLACE PROCEDURE OPS.SP_BRIDGE_UNFINISHED()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
    BEGIN TRANSACTION;
    INSERT INTO OPS.BRIDGE_DEMO VALUES ('o3', 80.00);
    RETURN 'Reached RETURN without COMMIT';
END;
$$;

-- Run separately: expect an error about an incomplete scoped transaction.
-- Snowflake rolls it back rather than returning the success text above.
CALL OPS.SP_BRIDGE_UNFINISHED();

SELECT * FROM OPS.BRIDGE_DEMO ORDER BY order_id;
-- CHECKPOINT: still o1/120 and o2/250; o3/80 was rolled back.

-- Compare the boundaries:
-- 1. BEGIN ... END groups scripting statements; it is not a transaction.
-- 2. A transaction started here must finish here with COMMIT or ROLLBACK.
-- 3. Leaving it open causes rollback and an error, even after a normal RETURN.
-- 4. With no explicit transaction and AUTOCOMMIT=TRUE, successful standalone
--    DML can already be committed before a later error occurs.
-- A caller-owned transaction is a different scope: the caller completes it.
-- Ending a Snowflake session rolls back any still-open transaction; do not
-- transfer SQL*Plus's default commit-on-EXIT behavior to this example.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 5 │ Local SQL routines and anonymous Python procedures
-- Run each example separately as one complete statement. These examples create
-- no persistent procedures and do not modify the pipeline or demonstration table.
-- Python runs inside Snowflake on ADV_WH, not on the student VM. Its packages
-- are specified below; the local VM virtual environment is not used here.
-- Allow additional time for these examples and the first Python startup.
-- ──────────────────────────────────────────────────────────────────────────────

-- Example A: A nested SQL procedure in an anonymous scripting block.
-- Declare counter before the nested procedure so the procedure can reference it.
-- Both calls modify the same enclosing variable. The routine is local to this
-- block; it cannot be called from a separate worksheet statement afterward.
EXECUTE IMMEDIATE $$
DECLARE
    counter INTEGER DEFAULT 0;

    increment_counter PROCEDURE()
        RETURNS INTEGER
        AS
        BEGIN
            counter := counter + 1;
            RETURN counter;
        END;

BEGIN
    CALL increment_counter();
    CALL increment_counter();

    RETURN counter;
END;
$$;
-- CHECKPOINT: 2. Running the whole block again starts counter at zero again.

-- Example B: The equivalent counter implemented in Python.
-- WITH ... CALL defines and invokes an anonymous procedure in one statement.
-- Do not execute the final CALL separately; counter_demo is not a stored object.
-- Snowflake supplies the session argument to main automatically.
-- increment_counter is a local Python function, not a Snowflake procedure.
-- nonlocal allows it to update counter in the enclosing main function.
WITH counter_demo AS PROCEDURE ()
RETURNS INTEGER
LANGUAGE PYTHON
RUNTIME_VERSION = '3.12'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
AS
$$
def main(session):
    counter = 0

    def increment_counter():
        nonlocal counter
        counter += 1
        return counter

    increment_counter()
    increment_counter()

    return counter
$$
CALL counter_demo();
-- CHECKPOINT: 2. Each invocation creates a fresh counter inside main.

-- Example C: Pass a SQL argument to an anonymous Python procedure.
-- The parameter list follows AS PROCEDURE, not the name double_py.
-- N is the SQL argument; Python receives its value as n after the supplied session.
-- Again, select and execute the entire WITH ... CALL statement together.
WITH double_py AS PROCEDURE (N INTEGER)
    RETURNS INTEGER
    LANGUAGE PYTHON
    RUNTIME_VERSION = '3.12'
    PACKAGES = ('snowflake-snowpark-python')
    HANDLER = 'main'
    AS
    $$
def main(session, n):
    return n * 2
$$
CALL double_py(21);
-- CHECKPOINT: 42. Change the argument to 7 and rerun the whole statement: 14.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 6 │ Clean up the disposable demonstration objects
-- ──────────────────────────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS OPS.SP_BRIDGE_APPLY(VARCHAR, NUMBER);
DROP PROCEDURE IF EXISTS OPS.SP_BRIDGE_UNFINISHED();
DROP PROCEDURE IF EXISTS OPS.SP_SAFE_DIVIDE(FLOAT, FLOAT);
DROP TABLE IF EXISTS OPS.BRIDGE_DEMO;

-- ACCEPTANCE CHECKPOINT (all must hold):
--   Step 1 returns 'HIGH' for 3200.00 and 'LOW' for 800.00.
--   Step 2: CALL SP_SAFE_DIVIDE(10, 2) returns 'Result is 5'; division by zero
--           returns handled error text containing 'Division by zero'.
--   Step 3: after the good call, BRIDGE_DEMO holds o1 and o2; after the conflicting
--           call, it still holds only o1 and o2 (no 999.00 row), and the call raises
--           error -20001.
--   Step 4: an unfinished-transaction error; o3/80 is absent after rollback.
--   Step 5: nested SQL counter returns 2; Python counter returns 2;
--           anonymous Python double_py(21) returns 42.
--   Pipeline untouched: BRONZE / SILVER / GOLD are never referenced in this lab.
-- Teaching notes:
--   - If the room is strong on scripting, cut Step 1 to a 2-minute demo and keep
--     Steps 2 and 3, discussing Step 4 briefly. Otherwise allow about 30 minutes
--     and pay for it from slide time, never from a core lab.
--   - The key idea before Lab 07: THIS procedure explicitly manages a transaction.
--     That is why Lab 07 says "create the procedure outside any explicit
--     transaction" — the procedure begins and commits (or rolls back) its own.
--     A stored procedure is not automatically one transaction simply because
--     it contains a BEGIN ... END scripting block.
-- Sources:
-- https://docs.snowflake.com/en/developer-guide/snowflake-scripting/exceptions
-- https://docs.snowflake.com/en/sql-reference/transactions
-- https://docs.snowflake.com/en/sql-reference/snowflake-scripting/declare
-- https://docs.snowflake.com/en/sql-reference/sql/call-with
