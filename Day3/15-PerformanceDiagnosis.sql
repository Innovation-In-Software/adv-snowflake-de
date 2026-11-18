/*----------------Snowflake Advanced 3-day class Lab:-------------------------------
-- Copyright © 2026 Innovation In Software Corporation. All rights reserved.
-- Diagnose before choosing an optimization
1) Read EXPLAIN, Query Profile and immediate query history
2) Capture query IDs and distinguish elapsed time components
3) Choose a hypothesis based on selectivity and physical work
----------------------------------------------------------------------------------*/

-- Diagram: Pipeline-progression.md, Lab 15 - Measure before tuning.
-- GOAL: Collect evidence about a query before choosing an optimization.
-- Method: predict the work -> execute and capture the query ID -> inspect actual
-- time and physical work -> state an observation -> propose the next experiment.
-- Run 15-PerformanceSetup.sql first and use the same worksheet session throughout.
-- This lab collects a baseline; Labs 16-20 test possible improvements.

USE ROLE ADV_LAB;
USE WAREHOUSE ADV_WH;
USE DATABASE ADV_ORDERS;
USE SCHEMA OPS;

ALTER SESSION SET TIMEZONE = 'UTC';

ALTER SESSION SET QUERY_TAG = 'ADV_2026_DAY3';

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1 │ Predict the work from a plan
-- ──────────────────────────────────────────────────────────────────────────────

-- Disable reuse of completed results so we can observe execution.
-- Warehouse data cache can still affect the run; inspect it in the profile.
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- QUESTION: We need only seven days of orders. How much data might be read?
-- Inspect the operations and compare partitionsAssigned with partitionsTotal.
-- The text version below presents the same plan in another format.

EXPLAIN 
SELECT COUNT(*), SUM(AMOUNT)
FROM PERF.ORDERS_BASE
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';


EXPLAIN USING TEXT
SELECT COUNT(*), SUM(AMOUNT)
FROM PERF.ORDERS_BASE
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

-- EXPLAIN is a plan prediction; it is not an execution measurement.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2 │ Execute the baseline and record its identity immediately
-- ──────────────────────────────────────────────────────────────────────────────

SELECT COUNT(*) AS ORDER_COUNT, SUM(AMOUNT) AS ORDER_AMOUNT
FROM PERF.ORDERS_BASE
WHERE ORDER_DATE BETWEEN DATE'2024-06-01' AND DATE'2024-06-07';

-- Record ORDER_COUNT and ORDER_AMOUNT for later correctness comparisons.
-- One aggregate result row does not mean only one order was processed.
-- Capture immediately after the measured query.
SET (BASELINE_QUERY_ID, BASELINE_CAPTURED_AT) = (LAST_QUERY_ID(), CURRENT_TIMESTAMP());

INSERT INTO PERF.MEASUREMENTS
VALUES ('DATE_BASELINE', $BASELINE_QUERY_ID, $BASELINE_CAPTURED_AT);


-- First separate execution from compilation and overload waiting (milliseconds).
-- A long elapsed time alone does not tell us which part needs improvement.
SELECT QUERY_ID, EXECUTION_TIME, COMPILATION_TIME, TOTAL_ELAPSED_TIME,
       BYTES_SCANNED,
       QUEUED_OVERLOAD_TIME
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 100))
WHERE QUERY_ID = $BASELINE_QUERY_ID;

-- Now inspect actual operator statistics, rather than the plan prediction.
-- The full output exposes the available metrics; the next query focuses on
-- operator time, row flow, and pruning.
SELECT * 
FROM TABLE(GET_QUERY_OPERATOR_STATS($BASELINE_QUERY_ID));

-- In Snowsight open the captured query's profile. Locate TableScan, filter,
-- aggregation, scanned partitions and cache indicators. Save an observation.
-- An operator-stat privilege or unsupported-query error is recorded separately;
-- the query ID and profile UI remain the primary evidence.

-- Find the dominant operator and inspect the scan's scanned/total partitions.
-- pct is the reported time fraction (0 to 1). Missing metrics may not apply
-- to an operator; do not interpret every NULL as zero work.
SELECT operator_type, 
       operator_statistics:input_rows::NUMBER                   AS input_rows, 
       operator_statistics:output_rows::NUMBER                  AS output_rows, 
       execution_time_breakdown:overall_percentage::FLOAT       AS pct, 
       operator_statistics:pruning:partitions_scanned::NUMBER   AS scanned, 
       operator_statistics:pruning:partitions_total::NUMBER     AS total 
FROM TABLE(GET_QUERY_OPERATOR_STATS($BASELINE_QUERY_ID))
ORDER BY pct DESC;

-- CHECKPOINT: Did the narrow date predicate actually eliminate partitions?
-- If TableScan dominates and most partitions are scanned, record both facts.
-- NEXT EXPERIMENT (Lab 16): Can organization by ORDER_DATE reduce scanning?
-- Use your actual measurements; partition counts and timings can vary.

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3 │ Compare a point lookup and a join workload
-- ──────────────────────────────────────────────────────────────────────────────

-- Apply the same diagnostic method to a different access pattern.
-- QUESTION: Does finding very few matching orders also require little reading?
SELECT ORDER_ID, ORDER_DATE, AMOUNT 
FROM PERF.ORDERS_BASE 
WHERE CUSTOMER_ID = 42 
ORDER BY ORDER_ID;

SET (LOOKUP_QUERY_ID, LOOKUP_CAPTURED_AT) = (LAST_QUERY_ID(), CURRENT_TIMESTAMP());

INSERT INTO PERF.MEASUREMENTS
VALUES ('POINT_BASELINE', $LOOKUP_QUERY_ID, $LOOKUP_CAPTURED_AT);

-- CHECKPOINT: 500 matching rows out of 50 million (0.001%).
-- Open LOOKUP_QUERY_ID in Query Profile, or reuse the Step 2 diagnostic queries
-- with $LOOKUP_QUERY_ID in place of $BASELINE_QUERY_ID.
-- Compare matching rows with actual partitions/bytes scanned; also inspect Sort.
-- NEXT EXPERIMENT (Lab 17): Can search optimization reduce sparse-lookup work?
-- Labs 17-19 use separate datasets and establish their own before/after baselines.

-- QUESTION: For this broader workload, does scan, join, or aggregation dominate?
SELECT C.REGION, SUM(O.AMOUNT) AS ACTIVE_AMOUNT
FROM PERF.ORDERS_BASE O
JOIN PERF.CUSTOMERS C ON O.CUSTOMER_ID = C.CUSTOMER_ID
WHERE O.STATUS = 'PAID'
GROUP BY C.REGION;

SET (JOIN_QUERY_ID, JOIN_CAPTURED_AT) = (LAST_QUERY_ID(), CURRENT_TIMESTAMP());

INSERT INTO PERF.MEASUREMENTS
VALUES ('JOIN_BASELINE', $JOIN_QUERY_ID, $JOIN_CAPTURED_AT);

-- Open JOIN_QUERY_ID in Query Profile, or reuse the Step 2 diagnostic queries
-- with $JOIN_QUERY_ID. Inspect each scan, row flow through the join, and spill.
-- A small grouped result can require substantial processing. Broad scanning
-- may be appropriate here; the presence of a join does not prove a bottleneck.
-- NEXT EXPERIMENT (Lab 20): Investigate cache, capacity, and concurrent load.
-- Its sizing workload omits the PAID filter; compare sizing runs within Lab 20.


SELECT * 
FROM PERF.MEASUREMENTS 
ORDER BY RECORDED_AT;

-- Diagnosis worksheet: predicate selectivity, partitions scanned, dominant
-- operator, spill, queueing, cache state, and proposed next experiment.
-- Write: "I observed [metric/value], so I propose [experiment]. If the hypothesis
-- is correct, [metric] should improve while the query result remains equivalent."
-- Zero spill or queueing is a valid observation; do not assume every symptom occurs.
-- Keep cache/load conditions comparable when testing changes in subsequent labs.
--
-- CONCLUSION: State which measured evidence best explains each workload's cost,
-- whether it supports your hypothesis, and which experiment should come next.
-- Name the metric that experiment should improve and verify the result stays
-- equivalent. This baseline motivates experiments; it does not prove a fix works.
--
-- QA TAKEAWAY (2026-11-17; ADV_QA_ORDERS on X-Small ADV_QA_WH):

-- Date: 479,452 rows / $124,655,461.53; 8/8 partitions scanned; TableScan
-- processed 163,906,048 bytes and accounted for 98.36% of operator time.
-- Execution 594 ms; history BYTES_SCANNED 700.25 MiB; overload queue 0 ms.

-- Point Lookup: 500 rows returned, but 8/8 partitions scanned; TableScan processed
-- 177,933,440 bytes (92.31% of operator time; 92.12% from cache).
-- Execution 254 ms; history BYTES_SCANNED 678.29 MiB; overload queue 0 ms.

-- Join: 42,857,142 paid fact rows; fact scan 8/8 partitions and 118,982,208
-- bytes (63.64% of operator time; 95.04% from cache). Customer scan: 100,000
-- rows, 1/1 partitions, 250,912 bytes. Aggregate accounted for 27.27%.
-- Execution 482 ms; history BYTES_SCANNED 678.20 MiB; overload queue 0 ms.
-- Caution: date, point lookup, and join ran sequentially on one warehouse. Result reuse
-- was disabled, but point lookup/join benefited from a warm warehouse cache.

-- Takeaway: neither selective predicate pruned partitions in this baseline.
-- Test date clustering (Lab 16) and sparse-lookup search optimization (Lab 17);
-- compare under controlled cache conditions and verify results remain equivalent.
-- Join evidence points to fact scanning and aggregation; investigate those metrics
-- before proposing a join-specific optimization.
--
-- Further experiments motivated by this evidence:
-- Lab 18: Date and customer queries need different access patterns. Investigate
-- an alternative customer-organized materialized view and verify actual scan
-- objects/pruning and optimizer rewrite. It is not an MV of this join aggregate.
-- Lab 19: Substantial scan bytes and execution time motivate checking QAS
-- eligibility. A large scan alone does not prove eligibility or actual QAS use.
-- Lab 20: Cache indicators, spill, execution time, and queueing guide separate
-- cache/sizing/concurrency experiments. Recovery is a separate operational topic.
