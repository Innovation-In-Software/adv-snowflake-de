# Day 3 — Evidence-based tuning and recovery

Open [Pipeline progression](Pipeline-progression.md) alongside the scripts to follow the objects and connections added by each lab.

Use the same account and original order project. Performance data lives in PERF. The instructor executes each numbered step and students repeat the same step. Do not promise a speedup: your profile determines the conclusion.


## Required before leaving class

Run **`99-CourseStop.sql`** and verify the final states. Closing Snowflake in the browser does not stop background work. Require all course tasks suspended, ORDERS_PIPE paused, and ADV_WH suspended; on Days 2-3 also stop the refresh/maintenance objects listed in that day's file. End any active notebook session using its controls. If a stop statement fails, resolve it and complete the remaining stops before leaving.

Auto-suspend can put an idle warehouse to sleep, but enabled task/refresh workloads can wake it again. In the Day 1 primary path, APPLY_TASK is deliberately left suspended; its resumed child does not independently run on a schedule. A false WHEN check does not start warehouse compute. Snowpipe ingestion and other serverless services have separate charges and are not stopped by suspending ADV_WH. This shutdown prevents further background work; it does not remove storage charges for preserved course data.

## Execute in order

1. `13-PerformanceSetup.sql` — 50 million deterministic orders and 100,000 customers generated with SQL. Verify scale, uniqueness and customer 42's 500 rows.
2. `14-PerformanceDiagnosis.sql` — disable result reuse in this session; capture date-filter, point-lookup and join query IDs; inspect scanning, operator work, spilling and queued time. Write a hypothesis before changing anything.
3. `15-ClusteringAndSearch.sql` — compare sorted and clustered tables side by side using EXPLAIN and query profiles, then load the same additional rows into both and compare again. Equal plans are a valid result; suspend automatic clustering afterward. A sorted CTAS is not automatic clustering.
4. `16-MaterializedViewsAndClustering.sql` — copy 150 million TPC-H orders, compare date and customer access patterns, and test a customer-clustered materialized view directly and through optimizer rewrite. Compare covered columns with `SELECT *`; suspend the view afterward. Requires access to `SNOWFLAKE_SAMPLE_DATA.TPCH_SF100`; use `Optional-QAS.sql` for query acceleration.
5. `17-WarehouseCacheAndRecovery.sql` — compare persisted results and warehouse cache; use a separate tuning warehouse for XS/Small comparison; optional concurrent worksheets; clone/drop/undrop a disposable table.
6. `18-CapstoneAndAcceptance.sql` — resume and refresh Gold after Day 2 shutdown, wait for the freshness checkpoint, recheck the business and policy contracts, justify a measured optimization, and describe recovery/freshness responsibilities.
7. `99-CourseStop.sql` — stop course tasks, pipe, Dynamic Tables, materialized-view maintenance and warehouses. Confirm any optional services are also stopped.

## Instructor rehearsal evidence

A prior one-million-row rehearsal put both layouts in one micro-partition, so it could not demonstrate date pruning; that remains a scale lesson, not the lab outcome. In the 50-million-row instructor rehearsal on an X-Small warehouse, generation took 6.8 seconds of query execution; the date-range EXPLAIN assigned 8/8 baseline partitions and 1/16 sorted partitions. Both queries returned 479,452 rows and $124,655,461.53 total amount; measured execution was 74 ms baseline versus 17 ms sorted, with 710,609,408 versus 31,742,976 bytes scanned. These figures are rehearsal evidence, not fixed student acceptance values—record each account's actual plan, profile and results, and do not promise a runtime speedup.

## Optional services

`Optional-SOS.sql`: Enterprise feature; wait for search optimization readiness before timing. Compare customer 42 under the same conditions and remove the service after the exercise.

`Optional-QAS.sql`: execute only for an eligible query and a validated account. Use its estimate to decide whether the 50-million-row workload qualifies; an ineligible estimate is a valid conclusion, and do not enable QAS to manufacture an improvement.

## Measurement worksheet

For each experiment record case, query ID, warehouse/size, cache settings, repetitions, result equality, partitions scanned/total, elapsed time, bytes scanned, spill, queue and maintenance costs. Separate compile time from execution and queued time. Keep individual runs; report a representative median only after repetitions.

## Recovery boundary

UNDROP verifies object recovery within retention in this account. It does not demonstrate regional failover. For disaster recovery specify RPO/RTO, eligible replication objects, account/region prerequisites, refresh schedule and a rehearsed consumer reconnection procedure. Do not describe these design answers as tested failover.

Copyright © 2026 Innovation In Software Corporation. All rights reserved.
