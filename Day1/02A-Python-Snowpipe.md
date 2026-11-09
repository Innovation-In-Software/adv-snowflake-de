# Lab 02A - Submit files through the Snowpipe REST API

Run after Lab 02 and before Lab 03. Reuse `EVENTS_STAGE`, `ORDERS_PIPE`, and `EVENTS_RAW`. Python uploads a new file containing the four existing batch-2 events, then calls the pipe's `insertFiles` endpoint. This intentionally increases Bronze deliveries from 8 to 12; Silver's current orders and Gold business totals remain unchanged after processing. The Silver inbox also preserves duplicate deliveries.

## Run

1. Pull the latest repository locally and in the Snowflake workspace. Complete Labs 01-02 and the local key-pair setup. Use the same training user in `.env` and Snowsight; use the `organization-account` account identifier.
2. Run `02A-Snowpipe-Setup.sql` in Snowsight. This sets your training user's default role to `ADV_LAB`; REST requests use that default role, not `SNOWFLAKE_ROLE` or a connector session role. No new stage or target is created.
3. From the local repository root:

```powershell
python -m pip install -r SetUp/requirements.txt
python Day1/02A-PythonSnowpipe.py
```

The script keeps only `Day1/rest_api_replay.json` (one JSON object per line) beside the Python script and prints its full path. Open it in your editor to inspect the four events. Each rerun regenerates this file; Git ignores it. `PUT AUTO_COMPRESS=TRUE` compresses it during upload, producing `rest_api_replay.json.gz` on the stage without keeping a second lab output locally.

The connector reads batch 2 from `VW_ORDER_EVENTS_SOURCE` and uploads `batch2/rest_api_replay.json.gz` to `EVENTS_STAGE`. The REST request is:

```text
POST /v1/data/pipes/ADV_ORDERS.BRONZE.ORDERS_PIPE/insertFiles
{"files": [{"path": "rest_api_replay.json.gz"}]}
```

The filename is relative to the pipe's `@EVENTS_STAGE/batch2/` source. Do not include `batch2/` again in the request. A key-pair JWT authenticates the request. The API queues the file; Snowpipe executes the existing pipe definition asynchronously on Snowflake-managed compute. The client polls `insertReport` and verifies four rows for this filename in Bronze. HTTP success alone does not prove that loading succeeded. No SQL API COPY or ALTER PIPE REFRESH is used by this client.

## Verify and repeat

```sql
USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA BRONZE;
SELECT source_file, COUNT(*) FROM EVENTS_RAW GROUP BY source_file ORDER BY source_file;
SELECT COUNT(*) FROM EVENTS_RAW;    -- 12
SELECT COUNT(*) FROM EVENTS_STREAM; -- 12 before Lab 03 consumes it
```

Expect three files with four rows each. The new filename demonstrates duplicate business events in another delivery. Run the Python script again with the SAME filename to demonstrate Snowpipe file tracking: during this rehearsal the total remains 12. PUT uses OVERWRITE=TRUE to allow replacing the staged file; unchanged content may still be skipped. Replacing a staged file does not clear Snowpipe file tracking. Do not rename it on retry, delete Bronze rows, or recreate the pipe. File tracking has finite retention; this is a same-rehearsal exercise, not a permanent deduplication guarantee.

On failure or timeout, inspect `SYSTEM$PIPE_STATUS` and `INFORMATION_SCHEMA.COPY_HISTORY` for `EVENTS_RAW`. A timeout does not cancel the queued load. Fix the issue and retry the same filename. Do not continue to Lab 03 until all four rows are confirmed.

## Downstream checkpoints

| Checkpoint | Bronze / pending stream or inbox |
|---|---:|
| Before Lab 03: Bronze / pending stream | 12 / 12 |
| After Lab 03: Bronze / Silver inbox | 12 / 12 |
| After Lab 04 and at Lab 05: Bronze / inbox | 14 / 14 |
| After Lab 06 replay: Bronze / inbox | 15 / 15 |

Current orders remain 3, rejected events remain 1, and the stream drains to 0 after processing. Gold active value is 150 after Lab 03 and 165 after Lab 04. Lab 02A is required in the planned sequence, and Lab 05 checks for its 14 deliveries.

Lab 02B continues to use its separate `DIR_EVENTS_STAGE` and `DIR_EVENTS_RAW`. It does not change these core totals. For a fresh rehearsal, rerun environment setup and start at Lab 01.

References: [Snowpipe REST workflow and default-role authentication](https://docs.snowflake.com/en/user-guide/data-load-snowpipe-rest-overview), [REST endpoints and file paths](https://docs.snowflake.com/en/user-guide/data-load-snowpipe-rest-apis).

Live account rehearsal of this revised extension is still required.

## JWT authentication

JWT means JSON Web Token: an encoded header and identity/time claims plus a digital signature. Our private key signs the token; Snowflake verifies it using the registered public key. The private key is not transmitted. The token is a short-lived credential, not encrypted storage for secrets.

The script uses SNOWFLAKE_ACCOUNT (organization-account) and SNOWFLAKE_USER from .env for JWT claims. The same account setting is used for the connector and REST hostname. Run the script without command-line options.
