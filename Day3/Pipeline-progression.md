# Day3 - Pipeline progression

Snowflake Advanced Data Engineering

These diagrams show intended structure at each lab checkpoint. Read the SQL comments and verify actual outputs; diagrams do not certify an untested run. Arrows are labelled data dependencies or control triggers. A view arrow means a query dependency, not a stored copy. The diagrams use plain Markdown code blocks and require no diagram renderer.

## Lab 13 - Independent performance sandbox

```text
SQL GENERATOR -> PERF.ORDERS_BASE (1,000,000)
SQL GENERATOR -> PERF.CUSTOMERS   (100,000)
captured query IDs -> PERF.MEASUREMENTS

Existing business pipeline stays separate: current=3 / active value=165
```

Create all performance tables in the initial setup section. CTAS defines and populates the generated fixtures together; it is intentional setup, not business ingestion. MEASUREMENTS stores case names and query IDs, not a guaranteed performance improvement.

## Lab 14 - Measure before tuning

```text
ORDERS_BASE -> date range / point lookup ----+
ORDERS_BASE + CUSTOMERS -> join -------------+-> query IDs -> MEASUREMENTS
                                             -> history / operator profile
```

No new table. Distinguish EXPLAIN predictions from measured execution. Capture query IDs immediately after each measured query. Record scanned partitions, bytes, spill, queueing and cache evidence where available.

## Lab 15 - Physical ordering comparison

```text
ORDERS_BASE -- sorted CTAS --> ORDERS_SORTED
      |                            |
      +---- same date predicate ---+
                    |
              totals / profiles -> MEASUREMENTS
```

Create ORDERS_SORTED at the start of this experiment. Compare exact totals, pruning and measured timing; sorted CTAS does not establish the long-term benefit or cost of automatic reclustering. Optional SOS adds a separate ORDERS_SEARCH copy and later removes its search service.

## Lab 16 - Materialized aggregates and QAS estimate

```text
ORDERS_BASE -> DAILY_ORDER_MV -> direct aggregate query
      |               ^
      +-> base query -+ optimizer may choose rewrite
captured query ID -> QAS eligibility estimate
                 -> optional ADV_QAS_WH experiment
```

The materialized view is a maintained output, created from its defining SELECT. Compare direct results and inspect whether a base query is actually rewritten. QAS estimation is not measured acceleration; optional execution uses a separate bounded warehouse.

## Lab 17 - Cache, compute and local recovery

```text
ORDERS_BASE + CUSTOMERS -> ADV_TUNE_WH (XS / Small)
                          -> measured query IDs -> MEASUREMENTS

ORDERS_BASE -- clone --> RECOVERY_COPY
                          -> DROP -> UNDROP -> verify restored count

Two student worksheets -> concurrent queries -> inspect queueing
```

Prepare RECOVERY_COPY before the experiments. The original business pipeline is untouched. Keep result-cache, warehouse-cache and sizing observations separate. Local UNDROP demonstrates recovery of this disposable copy, not cross-region readiness.

## Lab 18 - Capstone and shutdown

```text
Bronze -> Silver -> Dynamic Gold -> governed consumers
           |             |                 |
        state checks   freshness         role tests
Performance sandbox -> measured evidence -> defended design

Shutdown -> suspend tasks / pipe / DTs / MV / warehouses
         -> remove optional maintenance if enabled
```

No new table. Reconcile actual business state, consumer access and performance evidence. The stop script preserves objects and evidence while stopping services; optional services are stopped only if created. A diagram shows intended structure, not proof that every branch ran successfully.

## Table-first teaching sequence

Inspect existing inputs, define known base-table destinations, then develop connections and processing. Create views and procedures as their SELECTs and DML become understood. CTAS, Dynamic Tables and materialized views combine definition with population/maintenance and remain at the first step that has their required inputs. Disposable fixtures remain separate from the business project.

Copyright © 2026 Innovation In Software Corporation. All rights reserved.
