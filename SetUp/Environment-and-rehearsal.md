# Environment and rehearsal

## Uniform classroom profile

Use one fresh, dedicated Snowflake training account per person, including the instructor, with the same cloud, region, edition and feature settings. The core Day 1 design uses native tables and user-managed X-Small compute. Select Enterprise-capable training environments for later masking/row-access-policy labs; verify entitlements before class. AWS is required only for the optional internal-stage AUTO_INGEST preview branch as documented on 2026-10-09. Do not introduce mixed-cloud paths during a synchronous class.

Each person needs browser access, a SQL worksheet, and the ability to use ACCOUNTADMIN for the short, identical provisioning script. Return immediately to ADV_LAB for labs. In organization-managed accounts an authorized administrator must provision equivalent isolated resources per learner; this package's fixed names MUST NOT be used by multiple learners in one account. That alternative has not been authored or tested here.

Run 00-Environment.sql once, in sections. It creates ADV_LAB, ADV_WH, ADV_ORDERS and four schemas. No passwords are embedded. Setup deliberately avoids OR REPLACE and broad grants to PUBLIC. A name collision means stop and inspect, not overwrite.

Warehouse auto-suspend limits idle warehouse use; it is not a cap on Snowpipe or total account charges. Monitor classroom consumption and pause ingestion/tasks at day end. Do not promise a fixed lab cost before rehearsal.

## First-class preflight (30 minutes)

Instructor executes; all students repeat: sign in, confirm account/region, execute setup, confirm role and warehouse, execute SELECT 1. Compare outputs. Confirm everyone can create stage, stream, SQL procedure and task. Task owner ADV_LAB needs global EXECUTE TASK plus warehouse USAGE and access to referenced objects. No one proceeds to ingestion until all participants pass.

## Rehearsal and release

A single-account rehearsal completed on 2026-10-12. See the root Validation-report.md for actual coverage and remaining gates. The final warehouse definitions explicitly disable QAS to control inherited account defaults.

On a fresh account execute 00, then Day1 01–06, Day2 07–11 and Day3 13–18, observing every asynchronous pause; run each stop script. Capture account cloud/region, edition, CURRENT_VERSION(), date, role, query IDs, outputs, timings, task history and errors in Validation-report.md. Do not capture credentials. Repeat on a second student-equivalent account. Rehearse another clean run before early November; recheck preview scope and UI changes then. Fix and rerun affected paths before signing off.

## Reset boundaries

Do not reset midway to hide a failed checkpoint. Diagnose the stage, COPY history, inbox and stream first. For a complete rehearsal reset, finish in-flight tasks, run 99, confirm the dedicated account and exact ADV_ORDERS database, then deliberately remove only that lab database/warehouse/role through your normal account administration process. Reset DDL is not part of the student sequence. Never truncate Bronze or recreate a stream while preserving downstream state and call that a replay test.

If a lesson is interrupted, resume at its checkpoint. New worksheets must execute that script's USE statements. Keep identifiers fixed within each dedicated account.

Copyright © 2026 Innovation In Software Corporation. All rights reserved.
