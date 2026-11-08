# Optional Lab 02A - Local Python upload and Snowflake SQL API

This extension demonstrates client-driven orchestration: local Python creates JSON files, uploads them to an isolated internal stage, and submits `COPY INTO` through Snowflake's SQL API. It leaves the core `EVENTS_RAW` table unchanged so Lab 03 still starts with eight rows.

## Prerequisites

- Complete Labs 01-02 and verify the local key-pair login from `SetUp/key_pair_setup.py`.
- In the local repository's Python environment, install `SetUp/requirements.txt` so `PyJWT` and `requests` are available.
- In Snowsight, run `Optional-02A-SQLAPI-Setup.sql` as `ADV_LAB`.

## Run

From the local repository root, run:

```powershell
python Day1/Optional-02A-PythonSQLAPI.py
```

The script reads `VW_ORDER_EVENTS_SOURCE`, writes one JSON-lines file per batch to a temporary local folder, uploads both files with the Python connector to `API_EVENTS_STAGE`, and submits the `COPY INTO API_EVENTS_RAW` statement through the SQL API using a short-lived JWT signed by the existing private key. It polls the statement handle if Snowflake returns an asynchronous response.

Confirm the API response reports successful COPY work, then query:

```sql
SELECT COUNT(*) AS api_rows FROM ADV_ORDERS.BRONZE.API_EVENTS_RAW;
SELECT SOURCE_FILE, COUNT(*) AS rows_loaded
FROM ADV_ORDERS.BRONZE.API_EVENTS_RAW
GROUP BY SOURCE_FILE
ORDER BY SOURCE_FILE;
```

Expected result: eight rows total, four from each uploaded file. Re-running is safe for the same staged file names because the target is isolated and COPY load metadata prevents ordinary file replay from duplicating rows.

## Compare

The client performs two different jobs: the connector uploads local files, and the REST SQL API requests Snowflake to execute the load. The SQL API does not upload the local files. The client signs a short-lived JWT with the existing private key; it does not send the password to the API.

Snowflake SQL API references: [authentication](https://docs.snowflake.com/en/developer-guide/sql-api/authenticating), [submitting statements](https://docs.snowflake.com/en/developer-guide/sql-api/submitting-requests), and [handling responses](https://docs.snowflake.com/en/developer-guide/sql-api/handling-responses).

Copyright c 2026 Innovation In Software Corporation. All rights reserved.
