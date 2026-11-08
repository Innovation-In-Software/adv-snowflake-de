-- Optional Lab 02A | Client-driven load through the Snowflake SQL API
-- Run after Labs 01-02. This branch uses an isolated target and does not change
-- EVENTS_RAW or the expected starting state for Lab 03.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA BRONZE;

CREATE FILE FORMAT IF NOT EXISTS API_EVENTS_JSON
    TYPE = JSON
    COMPRESSION = AUTO;

CREATE STAGE IF NOT EXISTS API_EVENTS_STAGE
    FILE_FORMAT = API_EVENTS_JSON;

CREATE TABLE IF NOT EXISTS API_EVENTS_RAW
(
    payload VARIANT,
    source_file STRING,
    source_row NUMBER,
    scan_time TIMESTAMP_LTZ
);

SELECT COUNT(*) AS api_branch_rows_before
FROM API_EVENTS_RAW;
