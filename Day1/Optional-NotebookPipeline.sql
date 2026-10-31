/* Snowflake Advanced Data Engineering - optional notebook orchestration
Copyright © 2026 Innovation In Software Corporation. All rights reserved.
*/
-- This is a separately gated alternative, not an additional concurrent consumer.
-- The main Lab 06 procedure path remains the required route.
-- Import Snowpark-Pipeline.ipynb as a NOTEBOOK object named ORDER_PIPELINE
-- in ADV_ORDERS.OPS, owned by ADV_LAB; set query warehouse ADV_WH and add
-- snowflake-snowpark-python in its Packages settings. Choose a supported runtime.
-- A file visible in Workspace is not automatically an executable NOTEBOOK object.
-- Hosted import/runtime and headless execution MUST be rehearsed before class.
-- For newer Workspaces Code Bundles use that environment's deployment workflow;
-- do not substitute a Workspace file path for the NOTEBOOK object name below.
-- Sources:
-- https://docs.snowflake.com/en/sql-reference/sql/execute-notebook
-- https://docs.snowflake.com/en/sql-reference/sql/create-notebook

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

-- 1. Suspend the existing procedure consumer and wait for any run to finish.
-- ALTER TASK APPLY_TASK SUSPEND;
-- ALTER TASK AUDIT_TASK SUSPEND;
-- SHOW TASKS IN SCHEMA OPS;

-- 2. Configure the imported executable notebook, then manually validate it.
-- ALTER NOTEBOOK ORDER_PIPELINE SET QUERY_WAREHOUSE = ADV_WH;
-- EXECUTE NOTEBOOK ADV_ORDERS.OPS.ORDER_PIPELINE();
-- Verify current=3, active value=165, pending=0 and actual notebook run success.

-- 3. Only AFTER a successful manual notebook rehearsal, create this alternative.
-- CREATE OR REPLACE TASK NOTEBOOK_APPLY_TASK
--     WAREHOUSE = ADV_WH
--     WHEN SYSTEM$STREAM_HAS_DATA('ADV_ORDERS.BRONZE.EVENTS_STREAM')
-- AS
-- EXECUTE NOTEBOOK ADV_ORDERS.OPS.ORDER_PIPELINE();
-- First add a guarded replay so the WHEN condition has actual pending input.
-- INSERT INTO BRONZE.EVENTS_RAW
-- SELECT PAYLOAD, 'notebook/replay-e8', 1, CURRENT_TIMESTAMP()
-- FROM BRONZE.EVENTS_RAW
-- WHERE PAYLOAD:event_id::STRING = 'e8'
--   AND NOT EXISTS
--       (SELECT 1 FROM BRONZE.EVENTS_RAW WHERE SOURCE_FILE = 'notebook/replay-e8')
-- QUALIFY ROW_NUMBER() OVER (ORDER BY SOURCE_FILE, SOURCE_ROW) = 1;
-- EXECUTE TASK NOTEBOOK_APPLY_TASK;
-- Wait for task history SUCCEEDED; then verify stream=0, current=3, value=165.
-- After this manual task rehearsal, resume it to demonstrate triggered execution.
-- ALTER TASK NOTEBOOK_APPLY_TASK RESUME;
-- This standalone triggered task has no AUDIT_TASK child; inspect notebook and
-- task history plus business totals. Do not claim the original graph was executed.

-- 4. Restore the primary route after the comparison. Avoid two stream consumers.
-- ALTER TASK NOTEBOOK_APPLY_TASK SUSPEND;
-- ALTER TASK AUDIT_TASK RESUME;
-- Root APPLY_TASK stays suspended for deliberate manual class runs.
