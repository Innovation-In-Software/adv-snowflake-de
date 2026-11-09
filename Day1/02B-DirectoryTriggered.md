# Lab 02B - Directory table stream and triggered load task

This extension demonstrates Snowflake-managed event-driven orchestration: a directory-table stream detects stage metadata changes and a triggered task calls a procedure that consumes the stream and copies files into an isolated Bronze target. It leaves core `EVENTS_RAW` unchanged.

## Setup and file arrival

1. Run `02B-DirectoryTriggered.sql` as `ADV_LAB`, one numbered step at a time. Pause at Step 6 to verify results before Step 7 suspends the task. It creates a named internal stage with a directory table, the stream, an isolated target and event audit, a load procedure, and a triggered task.
The SQL script reuses `ADV_ORDERS.BRONZE.EVENTS_JSON` from Lab 01 (JSON/GZIP); a second file format is unnecessary.

2. Generate two files from the source view in Snowsight using the `COPY INTO @DIR_EVENTS_STAGE/...` statements below. These use the same per-batch JSON payloads as Lab 01:

```sql
COPY INTO @DIR_EVENTS_STAGE/batch1/events.json
FROM (SELECT payload FROM VW_ORDER_EVENTS_SOURCE WHERE batch = 1)
SINGLE = TRUE OVERWRITE = TRUE;

COPY INTO @DIR_EVENTS_STAGE/batch2/events.json
FROM (SELECT payload FROM VW_ORDER_EVENTS_SOURCE WHERE batch = 2)
SINGLE = TRUE OVERWRITE = TRUE;
```

3. Refresh directory metadata so the stream can observe the new files:

```sql
ALTER STAGE DIR_EVENTS_STAGE REFRESH;
```

4. Wait for the triggered task, then inspect `DIR_FILE_EVENTS`, `DIR_EVENTS_RAW`, and `TASK_HISTORY`. Confirm eight raw rows and two file events. The directory-table stream is consumed by the procedure's `INSERT`; `COPY INTO` load history prevents already-loaded files from being copied again.
5. Suspend the task when finished:

```sql
ALTER TASK DIR_EVENTS_LOAD_TASK SUSPEND;
```

## Compare

Here Snowflake detects file metadata changes and starts processing without a client submitting the `COPY INTO` request. Internal-stage directory metadata must be refreshed before the triggered task can detect the change; this lab uses explicit `ALTER STAGE ... REFRESH` so the event boundary is visible.

Snowflake references: [directory-table pipeline](https://docs.snowflake.com/en/user-guide/data-load-dirtables-pipeline), [triggered tasks](https://docs.snowflake.com/en/user-guide/tasks-triggered), and [directory tables](https://docs.snowflake.com/en/user-guide/data-load-dirtables).

Copyright c 2026 Innovation In Software Corporation. All rights reserved.
