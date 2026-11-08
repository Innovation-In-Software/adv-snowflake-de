-- Optional 02A: reuse Lab 02 objects; no new stage, pipe, or target.
-- The REST API uses the user's DEFAULT_ROLE, not the connector's session role.
-- Run as the same training user configured in the local .env.
USE ROLE ACCOUNTADMIN;
SET student_user = CURRENT_USER();
DESCRIBE USER IDENTIFIER($student_user); -- Record the previous default_role if needed.
ALTER USER IDENTIFIER($student_user) SET DEFAULT_ROLE = ADV_LAB;

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA BRONZE;
-- ADV_LAB owns ORDERS_PIPE and has the required database/schema access.
SELECT GET_DDL('PIPE', 'ADV_ORDERS.BRONZE.ORDERS_PIPE');
-- Confirm AUTO_INGEST=FALSE and source @EVENTS_STAGE/batch2/.
SELECT SYSTEM$PIPE_STATUS('ADV_ORDERS.BRONZE.ORDERS_PIPE');
-- If deliberately paused by 99-Stop.sql, resume before running the client:
-- ALTER PIPE ORDERS_PIPE SET PIPE_EXECUTION_PAUSED = FALSE;
SELECT COUNT(*) AS raw_rows FROM EVENTS_RAW; -- 8 before 02A; 12 after
SELECT COUNT(*) AS pending_rows FROM EVENTS_STREAM; -- 8 before; 12 after, before Lab 03
