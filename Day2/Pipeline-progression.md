# Day2 - Pipeline progression

Snowflake Advanced Data Engineering

These diagrams show intended structure at each lab checkpoint. Read the SQL comments and verify actual outputs; diagrams do not certify an untested run. Arrows are labelled data dependencies or control triggers. A view arrow means a query dependency, not a stored copy. The diagrams use plain Markdown code blocks and require no diagram renderer.

## Lab 07 - Verify the handoff

```text
Day 1: Bronze -> Silver current -> Gold view
                          |
                 baseline / role / feature checks
                          |
                 GOVERNANCE and CONSUMER schemas
```

No new processing table. Confirm current=3, active value=165 and no pending stream rows. Retain existing data and offsets; establish the supporting schemas and feature profile.

## Lab 08 - Declarative Dynamic Gold

```text
ORDERS_CURRENT ----+
                   | join -> ORDER_DETAIL_DT -> ORDER_METRICS_DT
ORDER_CONTACTS ----+          TARGET_LAG         five-minute goal
                              DOWNSTREAM
```

Define ORDER_CONTACTS first, then populate its reference data. Dynamic Table definitions create and maintain the outputs from SELECTs, so definition and processing are deliberately coupled. Create detail before its downstream metrics dependency. A controlled Silver correction changes value 165 -> 180; restore it to 165 and inspect actual refresh history.

## Lab 09 - Governed consumption boundary

```text
ORDERS_CURRENT -> ORDER_DETAIL_DT -> CONSUMER.ORDERS
                                      secure view
                                          ^
                              EMAIL_MASK + REGION_ACCESS
                                          |
                    US analyst / EU analyst / auditor role tests
```

No new base table. Attach masking, row-access policy and classification tag at the consumer view. US sees o1/o3; EU sees cancelled o2; auditor sees all rows and unmasked synthetic contacts. Disable secondary roles for tests; verify a source read is denied separately.

## Lab 10 - Quality and observability

```text
ORDER PIPELINE -> immediate SQL controls
               -> task / query / refresh history

SEPARATE QUALITY FIXTURE
DQ_DEMO -> NEGATIVE_AMOUNT_COUNT -> direct scalar result
                   |
              scheduled association -> monitoring results
```

Define DQ_DEMO first. Develop/evaluate the metric before its optional scheduled association. The demo contains 10, -5 and NULL: negative count=1. Scheduled evidence is asynchronous and entitlement-dependent; detach the metric and unset its schedule. These checks observe the pipeline; they do not change order state.

## Lab 11 - Consumers

```text
ORDER_DETAIL_DT -> CONSUMER.ORDERS -> US worksheet
                                      US-owned Streamlit / notebook
ORDER_METRICS_DT -> SHARE_US_METRICS -> optional aggregate sharing
```

No new base table. Consumers use the governed boundary. The app is owned by ADV_ANALYST_US and is US-scoped for all viewers; do not imply per-viewer role filtering. A separate view exposes only US aggregate metrics for the optional share branch.

## Lab 12 - Optional Iceberg interoperability

```text
PREVALIDATED ONLY
prepared storage / external volume
  -> prepared Snowflake Iceberg table
  -> metadata / snapshot reference -> DuckDB read
  -> compare row counts and values
```

This is an optional extension, not a mandatory completed node. Do not draw it as a working connection until storage, access and the external read are validated for students. Record BLOCKED if unavailable; preserve the core pipeline. No hidden instructor-only setup.

## Table-first teaching sequence

Inspect existing inputs, define known base-table destinations, then develop connections and processing. Create views and procedures as their SELECTs and DML become understood. CTAS, Dynamic Tables and materialized views combine definition with population/maintenance and remain at the first step that has their required inputs. Disposable fixtures remain separate from the business project.

Copyright © 2026 Innovation In Software Corporation. All rights reserved.
