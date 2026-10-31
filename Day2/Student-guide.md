# Day 2 — Governed and observable Gold

Open [Pipeline progression](Pipeline-progression.md) alongside the scripts to follow the objects and connections added by each lab.

Work in your own course account. The instructor executes a numbered step; everyone repeats that step and checks its result before continuing. Select statement groups rather than executing the entire course as one batch. Scheduled operations require an explicit wait for evidence.


## Required before leaving class

Run **`99-Day2-Stop.sql`** and verify the final states. Closing Snowflake in the browser does not stop background work. Require all course tasks suspended, ORDERS_PIPE paused, and ADV_WH suspended; on Days 2-3 also stop the refresh/maintenance objects listed in that day's file. End any active notebook session using its controls. If a stop statement fails, resolve it and complete the remaining stops before leaving.

Auto-suspend can put an idle warehouse to sleep, but enabled task/refresh workloads can wake it again. In the Day 1 primary path, APPLY_TASK is deliberately left suspended; its resumed child does not independently run on a schedule. A false WHEN check does not start warehouse compute. Snowpipe ingestion and other serverless services have separate charges and are not stopped by suspending ADV_WH. This shutdown prevents further background work; it does not remove storage charges for preserved course data.

## Before starting

Complete Day 1 through `06-Snowpark-Development.ipynb`. Expected state: 11 raw and inbox rows, three current orders, one BAD_AMOUNT rejection, no pending stream rows, two active US orders totaling USD 165. Suspend the root task between demonstrations. Use the same ADV_ORDERS objects throughout.

The core policy, masking and scheduled data-quality branches require an appropriate account edition and privileges. All students need the same enabled features; an instructor-only demonstration does not satisfy a hands-on objective. The preflight and final validation report identify any remaining account-specific restrictions.

## Execute in order

1. `07-Day2-Preflight.sql` — establish state and schemas. Resolve a failed business checkpoint before creating Gold.
2. `08-DynamicGold.sql` — create the detail and aggregate Dynamic Tables, inspect actual refresh mode/history, and demonstrate a reversible USD 180 → 165 change. Wait for each refresh to succeed.
3. `09-GovernedGold.sql` — create three roles in every environment; apply view policies; test US, EU and auditor. Execute the expected denied Silver read separately, then restore ADV_LAB. Keep secondary roles disabled for these tests.
4. `10-QualityAndObservability.sql` — immediate checks, custom metric, scheduled monitoring and execution/freshness evidence. Pause after attaching the metric until its result is visible, then detach it. An empty results query is not success.
5. `11-GoldConsumers.sql` — consume the US contract; create a Snowflake-hosted Streamlit app using `Streamlit-Gold.py`. The app runs with its owner's US role. It does not automatically adopt each viewer's region. The optional `Governed-Gold.ipynb` provides narrative practice in a Snowflake-hosted notebook.
6. `99-Day2-Stop.sql` — suspend refreshes and compute after class; retain course data.

## Optional branches

`Optional-DataShare.sql` requires a second authorized account. Run the provider grants, then confirm exactly what the consumer can see. A created share without a consumer test is incomplete.

`12-OptionalIceberg.sql` and `Optional-Iceberg-DuckDB.md` are a prevalidated interoperability demonstration, maximum 30 minutes. Run only when the documented storage, authentication, permissions and engine versions have been rehearsed. Metadata inspection alone does not establish interoperability. All required preparation must be reproducible by students if used as a hands-on lab.

## Acceptance

- US role sees o1/o3 with masked contact; EU sees cancelled o2 with masked contact; auditor sees all three contacts.
- US cannot read Silver directly.
- Gold remains USD 165 after the reversible refresh demonstration.
- Quality checks report zero current-state failures and preserve the rejected event.
- A scheduled measurement has an actual timestamp/value, or is explicitly recorded as blocked.
- Streamlit and notebook outputs are tested separately from SQL policy tests.

Copyright © 2026 Innovation In Software Corporation. All rights reserved.
