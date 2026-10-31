# Day 3 — Evidence-based tuning and recovery

Open [Pipeline progression](Pipeline-progression.md) alongside the scripts to follow the objects and connections added by each lab.

Use the same account and original order project. Performance data lives in PERF. The instructor executes each numbered step and students repeat the same step. Do not promise a speedup: your profile determines the conclusion.


## Required before leaving class

Run **`99-CourseStop.sql`** and verify the final states. Closing Snowflake in the browser does not stop background work. Require all course tasks suspended, ORDERS_PIPE paused, and ADV_WH suspended; on Days 2-3 also stop the refresh/maintenance objects listed in that day's file. End any active notebook session using its controls. If a stop statement fails, resolve it and complete the remaining stops before leaving.

Auto-suspend can put an idle warehouse to sleep, but enabled task/refresh workloads can wake it again. In the Day 1 primary path, APPLY_TASK is deliberately left suspended; its resumed child does not independently run on a schedule. A false WHEN check does not start warehouse compute. Snowpipe ingestion and other serverless services have separate charges and are not stopped by suspending ADV_WH. This shutdown prevents further background work; it does not remove storage charges for preserved course data.

## Execute in order

1. `13-PerformanceSetup.sql` — one million deterministic orders and 100,000 customers generated with SQL. Verify scale, uniqueness and customer 42's ten rows. Disable result reuse for baseline experiments.
2. `14-PerformanceDiagnosis.sql` — capture date-filter, point-lookup and join query IDs; inspect scanning, operator work, spilling and queued time. Write a hypothesis before changing anything.
3. `15-ClusteringAndSearch.sql` — compare physically date-sorted and baseline tables using identical predicates/results. Inspect pruning; repeat measurements with a stated cache condition. A sorted CTAS is not automatic clustering.
4. `16-MaterializedViewsAndQAS.sql` — create a maintained aggregate, prove aggregate equality, and inspect whether the optimizer selects it. Evaluate QAS eligibility without enabling service by default.
5. `17-WarehouseCacheAndRecovery.sql` — compare persisted results and warehouse cache; use a separate tuning warehouse for XS/Small comparison; optional concurrent worksheets; clone/drop/undrop a disposable table.
6. `18-CapstoneAndAcceptance.sql` — recheck the business and policy contracts, justify a measured optimization, and describe recovery/freshness responsibilities.
7. `99-CourseStop.sql` — stop course tasks, pipe, Dynamic Tables, materialized-view maintenance and warehouses. Confirm any optional services are also stopped.

## Measured limitation in the rehearsal account

The one-million-row fixture occupied one micro-partition on 2026-10-12. Both baseline and date-sorted tables therefore scanned one of one partitions. Use it to inspect evidence and result equality; it does not establish pruning savings. QAS reported NO_LARGE_ENOUGH_SCAN, and the optimizer retained the base-table scan after MV creation. No speedup is promised. A larger cost-bounded rehearsal requires approval before changing the fixture size.

## Optional services

`Optional-SOS.sql`: Enterprise feature; wait for search optimization readiness before timing. Compare customer 42 under the same conditions and remove the service after the exercise.

`Optional-QAS.sql`: execute only for an eligible query and a validated account. The one-million-row fixture may be too small to benefit. An ineligible estimate is a valid conclusion; do not enable QAS to manufacture an improvement.

## Measurement worksheet

For each experiment record case, query ID, warehouse/size, cache settings, repetitions, result equality, partitions scanned/total, elapsed time, bytes scanned, spill, queue and maintenance costs. Separate compile time from execution and queued time. Keep individual runs; report a representative median only after repetitions.

## Recovery boundary

UNDROP verifies object recovery within retention in this account. It does not demonstrate regional failover. For disaster recovery specify RPO/RTO, eligible replication objects, account/region prerequisites, refresh schedule and a rehearsed consumer reconnection procedure. Do not describe these design answers as tested failover.

Copyright © 2026 Innovation In Software Corporation. All rights reserved.
