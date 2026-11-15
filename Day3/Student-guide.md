# Day 3 — Evidence-based tuning and recovery

Open [Pipeline progression](Pipeline-progression.md) alongside the scripts to follow the objects and connections added by each lab.

Use the same account and original order project. Performance data lives in PERF. The instructor executes each numbered step and students repeat the same step. Do not promise a speedup: your profile determines the conclusion.


## Required before leaving class

Run **`99-CourseStop.sql`** and verify the final states. Closing Snowflake in the browser does not stop background work. Require all course tasks suspended, ORDERS_PIPE paused, and ADV_WH suspended; on Days 2-3 also stop the refresh/maintenance objects listed in that day's file. End any active notebook session using its controls. If a stop statement fails, resolve it and complete the remaining stops before leaving.

Auto-suspend can put an idle warehouse to sleep, but enabled task/refresh workloads can wake it again. In the Day 1 primary path, APPLY_TASK is deliberately left suspended; its resumed child does not independently run on a schedule. A false WHEN check does not start warehouse compute. Snowpipe ingestion and other serverless services have separate charges and are not stopped by suspending ADV_WH. This shutdown prevents further background work; it does not remove storage charges for preserved course data.

## Execute in order

1. **Lab 15:** `15-PerformanceSetup.sql`, then `15-PerformanceDiagnosis.sql` — generate the 50-million-row fixture and measure query profiles before tuning.
2. **Lab 16:** `16-ClusteringAndSearch.sql` — compare sorted and clustered layouts and suspend automatic clustering afterward.
3. **Lab 17:** `17-SearchOptimization.sql` — compare customer lookups before and after SOS; wait for readiness and clean up the isolated resources.
4. **Lab 18:** `18-MaterializedViewsAndClustering.sql` — compare access patterns and a customer-clustered materialized view using SF100 sample orders. Remove the restart task and procedure, suspend the view, and drop the dedicated `LAB16_WH`.
5. **Lab 19:** `19-QueryAcceleration.sql` — test QAS eligibility and service usage using the dedicated warehouse; drop it afterward.
6. **Lab 20:** `20-WarehouseCacheAndRecovery.sql` — compare caching and warehouse sizes, then clone/drop/undrop a disposable table.
7. **Lab 21:** `21-AWS-External-Function.ipynb` — build, test and clean up the Snowflake and AWS resources; requires an AWS account and a Snowflake-hosted notebook.
8. `99-CourseStop.sql` — stop course tasks, pipe, Dynamic Tables, maintenance and warehouses.

## Instructor rehearsal evidence

A prior one-million-row rehearsal put both layouts in one micro-partition, so it could not demonstrate date pruning; that remains a scale lesson, not the lab outcome. In the 50-million-row instructor rehearsal on an X-Small warehouse, generation took 6.8 seconds of query execution; the date-range EXPLAIN assigned 8/8 baseline partitions and 1/16 sorted partitions. Both queries returned 479,452 rows and $124,655,461.53 total amount; measured execution was 74 ms baseline versus 17 ms sorted, with 710,609,408 versus 31,742,976 bytes scanned. These figures are rehearsal evidence, not fixed student acceptance values—record each account's actual plan, profile and results, and do not promise a runtime speedup.

## Service considerations

`17-SearchOptimization.sql`: copy SF100 sample orders to an independent table and compare a customer lookup before and after search optimization on a dedicated warehouse. Wait for readiness, inspect actual pruning, and drop the table and warehouse afterward; storage and serverless maintenance incur charges.

`19-QueryAcceleration.sql`: compare SF1 and SF1000 sample queries on a dedicated warehouse; check eligibility before enabling QAS, then inspect actual service usage and cost. The SF1000 scan was eligible in QA, but eligibility and acceleration can vary. Drop the dedicated warehouse afterward.

## Measurement worksheet

For each experiment record case, query ID, warehouse/size, cache settings, repetitions, result equality, partitions scanned/total, elapsed time, bytes scanned, spill, queue and maintenance costs. Separate compile time from execution and queued time. Keep individual runs; report a representative median only after repetitions.

## Recovery boundary

UNDROP verifies object recovery within retention in this account. It does not demonstrate regional failover. For disaster recovery specify RPO/RTO, eligible replication objects, account/region prerequisites, refresh schedule and a rehearsed consumer reconnection procedure. Do not describe these design answers as tested failover.

Copyright © 2026 Innovation In Software Corporation. All rights reserved.
