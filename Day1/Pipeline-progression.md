# Day1 - Pipeline progression

Snowflake Advanced Data Engineering

These diagrams show intended structure at each lab checkpoint. Read the SQL comments and verify actual outputs; diagrams do not certify an untested run. Arrows are labelled data dependencies or control triggers. A view arrow means a query dependency, not a stored copy. The diagrams use plain Markdown code blocks and require no diagram renderer.

## Lab 01 - Source data and staged files

```text
ORDER_EVENTS_SOURCE (batch, payload)
  -> SQL unload using EVENTS_JSON
  -> EVENTS_STAGE / batch1 and batch2 files
```

Add the repeatable synthetic order-event source table, JSON file format and internal stage. No Bronze destination or processing stream is created here. Staged files contain full order states, including the identical e2 replay and the invalid e3 amount.

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

## Lab 03 - Bronze to current Silver state

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

Define both Silver tables first. Develop SELECTs before their views, then demonstrate DML with ROLLBACK before creating the reusable procedure. Identical deliveries remain in the inbox. QUALIFY selects one latest valid state per order; conflicting reuse of an event ID stops processing. e3 remains BAD_AMOUNT; e6 establishes a later valid o3 state. First-pass committed counts: inbox 8, current 3, rejects 1, pending 0; active value 150.

## Lab 04 - Task orchestration and Gold

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

Add RUN_AUDIT, the Gold view and a two-task graph. The root stays suspended; the child is resumed. REFRESH and EXECUTE TASK are separate asynchronous requests, for ingestion and processing respectively. PREFIX is relative to the pipe stage path batch2/: it matches update.json.gz. Wait for raw=10, not ten minutes; stream=2 before processing. Then inspect the matching graph run until both tasks succeed. Expected result: current orders 3; US active orders 2 / value 165; stream 0. Gold is a view dependency, not another task. A later empty-stream execution tests the condition.

## Lab 05 - Acceptance and rollback evidence

```text
BUSINESS PIPELINE (unchanged)
Bronze -> inbox -> current Silver -> Gold
                         |
                  exact-state / total checks

SEPARATE ROLLBACK DEMONSTRATION
STREAM_DEMO -> STREAM_DEMO_CHANGES -> STREAM_DEMO_SINK
                           INSERT inside BEGIN ... ROLLBACK
```

Part A states the expected data, shows expected/actual control totals and uses INTERSECT to display all matching rows: 3 current orders, 1 Gold row and 1 rejected event. Row-count controls must also pass, because INTERSECT alone does not expose extra actual rows. Part B is a separate helper demonstration; create its disposable tables and stream immediately before that demonstration, after acceptance. After rollback the demonstration stream still exposes its one inserted row and the sink has zero rows. No new business-processing stage is added. Run before Lab 06: acceptance expects raw/inbox=10.

## Lab 06 - Snowpark development and deployment

Development notebook: inspect typed/classified/enriched DataFrames -> validate latest candidates against SQL -> trial Snowpark writes/MERGE -> ROLLBACK -> assemble reusable handler -> deploy through SQL cells in the same notebook. The diagram below is the deployed processing path; the development trial does not consume the stream; the later deployed handler captures and commits stream data.

```text
EXISTING: EVENTS_STREAM -> EVENT_INBOX
                               |
                          Snowpark handler
                               |
REGION_REFERENCE -- join ------+
                               v
                         ORDER_EVENTS_ENRICHED
                         (typed / classified / enriched)
                               |
                      valid / unique / latest
                               v
                       ORDER_STATE_CANDIDATES
                               |
                             MERGE
                               v
                         ORDERS_CURRENT -> Gold

APPLY_TASK -> SP_APPLY_EVENTS_SNOWPARK -> AUDIT_TASK -> RUN_AUDIT
```

Define reference, transformed-event and candidate tables before filling or processing them. Python executes inside Snowflake. Develop the transformations first in `06-Snowpark-Development.ipynb`, then deploy identical functions as SP_APPLY_EVENTS_SNOWPARK and replace the task entry point. The unpinned Snowpark package resolves at procedure creation. The optional pipeline notebook is a separately gated alternative consumer, not part of this task graph. One synthetic raw replay bypasses stage/Snowpipe intentionally to isolate business idempotency. Expected final raw/inbox=11, current=3, rejects=1, pending=0, active value=165. Compare SQL and Snowpark results before calling the deployment successful.

## Table-first teaching sequence

Inspect existing inputs, define known base-table destinations, then develop connections and processing. Create views and procedures as their SELECTs and DML become understood. CTAS, Dynamic Tables and materialized views combine definition with population/maintenance and remain at the first step that has their required inputs. Disposable fixtures remain separate from the business project. Lab 05 is an explicit exception: its helper objects are created only when the separate demonstration begins.

Copyright © 2026 Innovation In Software Corporation. All rights reserved.
