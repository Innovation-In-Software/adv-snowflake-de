# Lab 06 validation - 2026-10-12

Isolated live Snowflake rehearsal; student ADV_ORDERS was not changed.

- Notebook transformation and rollback cells ran in Snowflake Python 3.12 as a temporary rehearsal stored-procedure wrapper, using the same cell source. Only session acquisition/context were adapted. All assertions passed.
- Unpinned Snowpark dependency resolved at deployment; see execution evidence below for the actual version.
- Initial input/inbox 10; current 3; active value 165; pending 0. Trial scratch writes rolled back.
- Procedure setup/handler rerun passed. Synthetic replay produced raw/inbox 11, scratch events 11, current 3, active value 165 and pending 0. Repeating replay did not add another row.
- Snowpark MERGE restored one deliberately missing order and one deliberately older order state.
- Conflicting e4 payload raised an exception: inbox remained 11, raw 12, pending stream 1, current 3 and active value 165. Transaction rollback preserved stream availability.
- Rehearsal warehouse suspended afterwards.

Not tested: hosted notebook UI import/runtime, optional headless notebook task, and task-graph execution in this rehearsal. These require an account rehearsal; do not present them as passed. Snowpipe was bypassed by SQL-seeded Bronze input in this test.

```json
{
  "status": "PASS",
  "database": "ADE_LAB6_REVIEW_20261012_210812",
  "notebook_code": {
    "NOTEBOOK_CELL_REHEARSAL": "Notebook development cells passed; Snowpark 1.55.1"
  },
  "initial": {
    "RAW_ROWS": 10,
    "INBOX_ROWS": 10,
    "PENDING_ROWS": 0,
    "CURRENT_ORDERS": 3,
    "ACTIVE_AMOUNT": "165.00",
    "SNOWPARK_ROWS": 10
  },
  "after_replay": {
    "RAW_ROWS": 11,
    "INBOX_ROWS": 11,
    "PENDING_ROWS": 0,
    "CURRENT_ORDERS": 3,
    "ACTIVE_AMOUNT": "165.00",
    "SNOWPARK_ROWS": 11
  },
  "conflict_rollback": {
    "RAW_ROWS": 12,
    "INBOX_ROWS": 11,
    "PENDING_ROWS": 1,
    "CURRENT_ORDERS": 3,
    "ACTIVE_AMOUNT": "165.00",
    "SNOWPARK_ROWS": 11
  },
  "limitations": [
    "Notebook UI import and execution not tested; notebook cells ran in an isolated Python stored procedure.",
    "Optional headless notebook task not executed.",
    "Existing task graph modification is retained but not executed in this rehearsal."
  ]
}
```

## Instructor notebook adoption - 12 October 2026

Retained the instructor 24-cell structure, SQL cell metadata, whitespace and df/df_* parameter naming. Applied equivalent formatting and parameter naming to deployment source. VERSION now intentionally uses NUMBER(3,1), a classroom simplification approved by the instructor. Numeric conversion can round additional fractional digits and rejects values outside this precision; full arbitrary-input validation is not claimed. Fresh scratch-table DDL uses this type; existing scratch tables are preserved by IF NOT EXISTS.

Live isolated rehearsal in ADE_LAB6_STYLE_20261012_010951: Python development cells and rollback assertions passed; the assembled handler passed two calls; current orders=3, active value=165 and stream=0. Inputs were copied from the accepted 11-delivery inbox. The conflict view was an empty fixture: no new conflict-guard test is claimed. Hosted notebook UI import/execution and optional notebook task were not tested. Warehouse suspended afterwards.

## Single-notebook consolidation — 12 October 2026

SQL setup, existing instructor-edited Python development cells, procedure deployment, task graph changes and checks now share 06-Snowpark-Development.ipynb. Python source parses; embedded handler matches Snowpark-OrderTransform.py exactly. Existing live handler and reversible-trial validation remains applicable to the unchanged transformations. This consolidation has not been executed through the Snowflake notebook UI; mixed SQL-cell context, package setup and asynchronous pauses require classroom-host rehearsal. No new full task-graph pass is claimed. The former SQL companion is archived; diagrams and slide references are tracked in TODO.
