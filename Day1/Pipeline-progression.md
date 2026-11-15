# Day1 - Pipeline progression

Snowflake Advanced Data Engineering

These diagrams show intended structure at each lab checkpoint. Read the SQL comments and verify actual outputs; diagrams do not certify an untested run. Arrows are labelled data dependencies or control triggers. A view arrow means a query dependency, not a stored copy. The diagrams use plain Markdown code blocks and require no diagram renderer.

## Lab 01 - Source data and staged files

```text
VW_ORDER_EVENTS_SOURCE view (batch, payload)
  -> SQL unload using EVENTS_JSON
  -> EVENTS_STAGE / batch1 and batch2 files
```

Add a view over repeatable synthetic order-event values, a JSON file format and an internal stage. The view is the simulated source; it does not persist another copy of the mock data. No Bronze destination or processing stream is created here. Staged files contain full order states, including the identical e2 replay and the invalid e3 amount.

## Lab 02 - File ingestion into Bronze

```text
EVENTS_STAGE / batch1 -- COPY INTO ------------------+
                                                    v
EVENTS_STAGE / batch2 -- ORDERS_PIPE ------------> EVENTS_RAW
                         ^                          |
                         | manual REFRESH           | tracked inserts
                         |                          v
                      Instructor               EVENTS_STREAM
                                               (table offset)
```

Add EVENTS_RAW, its append-only stream and ORDERS_PIPE. Create the stream before loading the files. COPY loads batch1; Snowpipe loads batch2. AUTO_INGEST is FALSE; REFRESH is the explicit classroom loading trigger. The stream tracks the source table history rather than storing another copy of its rows. Expected first-pass Bronze count: 8; pending stream rows: 8.

## Lab 03 - Snowpipe REST API

```text
VW_ORDER_EVENTS_SOURCE batch 2 -> local JSON/GZIP -> PUT -> EVENTS_STAGE/batch2/
Python insertFiles request (JWT) -> ORDERS_PIPE -> EVENTS_RAW
```

The client submits `rest_api_replay.json.gz` relative to the pipe's batch2/ path. The new file adds four duplicate business-event deliveries: Bronze and pending stream counts become 12. Repeating the same filename during rehearsal tests file tracking. Silver retains the deliveries in its inbox but keeps the same current business state. See [Lab 03](03-Python-Snowpipe.md) for both checkpoint paths.

## Lab 04 - Directory-table triggered load

```text
DIR_EVENTS_STAGE -> directory table -> DIR_EVENTS_STAGE_STREAM
        ^                                      |
        | explicit ALTER STAGE REFRESH         | WHEN stream has data
        +---------------------------------- DIR_EVENTS_LOAD_TASK
                                                   |
                                         SP_LOAD_DIRECTORY_STAGE_FILES
                                                   |
                                         COPY INTO DIR_EVENTS_RAW
```

The task starts after refreshed directory metadata changes. The procedure consumes the directory stream into `DIR_FILE_EVENTS`, then COPY scans the isolated stage; Snowflake load history skips files already loaded to the extension target. Suspend the task after the demonstration. This extension leaves core `EVENTS_RAW` unchanged.

## Lab 05 - Snowpipe Streaming

```text
Python producer -> named channel -> streaming pipe -> isolated EVENTS table
```

Wait for the committed offset and verify three rows. This exercise does not change the business pipeline. Clean up the separate schema and warehouse.

## Lab 06 - SQL scripting bridge

Use disposable objects to practice blocks, procedures, transaction ownership and exception handling before building Silver.

## Lab 07 - Bronze to current Silver state

```text
EVENTS_RAW -> EVENTS_STREAM -- INSERT --> EVENT_INBOX
                                           |
                                           v
                                      VW_TYPED_EVENTS
                                           |
                                           v
                                     VW_CLASSIFIED_EVENTS
                                       /    |     \
                                      v     v      v
                             VW_REJECTED_EVENTS |  VW_EVENT_CONFLICTS
                                            |
                                valid latest candidate / order
                                            |
                                          MERGE
                                            v
                                      ORDERS_CURRENT

SP_APPLY_EVENTS wraps INSERT + conflict guard + MERGE in one transaction.
```

Define both Silver tables first. Develop SELECTs before their views, then demonstrate DML with ROLLBACK before creating the reusable procedure. Identical deliveries remain in the inbox. QUALIFY selects one latest valid state per order; conflicting reuse of an event ID stops processing. e3 remains BAD_AMOUNT; e6 establishes a later valid o3 state. With required Lab 03, committed counts are inbox 12, current 3, rejects 1, pending 0; active value 150.

## Lab 08 - Task orchestration and Gold

```text
DATA PATH
update.json.gz (two e8 deliveries)
  -> ORDERS_PIPE -> EVENTS_RAW -> EVENTS_STREAM
  -> SP_APPLY_EVENTS -> EVENT_INBOX -> validation / selection
  -> ORDERS_CURRENT -> GOLD.VW_ORDER_METRICS (live view)
                 \
                  -> aggregate snapshot -> OPS.RUN_AUDIT

CONTROL PATH
ALTER PIPE ... REFRESH PREFIX = 'update' -> request Snowpipe load
EXECUTE TASK APPLY_TASK -> check WHEN -> CALL SP_APPLY_EVENTS
                                      |
                              successful completion
                                      v
                                 AUDIT_TASK
                              INSERT into RUN_AUDIT
```

Add RUN_AUDIT, the Gold view and a two-task graph. The root stays suspended; the child is resumed. REFRESH and EXECUTE TASK are separate asynchronous requests, for ingestion and processing respectively. PREFIX is relative to the pipe stage path batch2/: it matches update.json.gz. Wait for raw=14; stream=2 before processing. Then inspect the matching graph run until both tasks succeed. Expected result: current orders 3; US active orders 2 / value 165; stream 0. Gold is a view dependency, not another task. A later empty-stream execution tests the condition.

## Lab 09 - Acceptance evidence

```text
BUSINESS PIPELINE (unchanged)
Bronze -> inbox -> current Silver -> Gold
                         |
                  exact-state / total checks

```

Part A states the expected data, shows expected/actual control totals and uses INTERSECT to display all matching rows: 3 current orders, 1 Gold row and 1 rejected event. Row-count controls must also pass, because INTERSECT alone does not expose extra actual rows. Part B uses disposable objects to demonstrate rollback. Then `09-ChangesClause.sql` compares fixed-interval CHANGES queries with stream offsets. No business-processing stage is added. Acceptance expects raw/inbox=14.

## Table-first teaching sequence

Inspect existing inputs, define known base-table destinations, then develop connections and processing. Create views and procedures as their SELECTs and DML become understood. CTAS, Dynamic Tables and materialized views combine definition with population/maintenance and remain at the first step that has their required inputs. Disposable fixtures remain separate from the business project. Lab 09 is an explicit exception: its helper objects are created only when the separate demonstration begins.

Copyright © 2026 Innovation In Software Corporation. All rights reserved.
