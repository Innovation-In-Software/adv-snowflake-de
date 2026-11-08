# Environment and rehearsal

## Uniform classroom profile

Naming convention: ordinary and secure views use the `VW_` prefix; materialized views use `MVW_`; stored procedures use `SP_`. Tables and dynamic tables retain their existing names. The scripts and diagrams use these names consistently. Updating course files does not rename objects already created in a Snowflake account.

Use one fresh, dedicated Snowflake training account per person, including the instructor, with the same cloud, region, edition and feature settings. The core Day 1 design uses native tables and user-managed X-Small compute. Select Enterprise-capable training environments for later masking/row-access-policy labs; verify entitlements before class. AWS is required only for the optional internal-stage AUTO_INGEST preview branch as documented on 2026-10-09. Do not introduce mixed-cloud paths during a synchronous class.

Each person needs browser access, a SQL worksheet, and the ability to use ACCOUNTADMIN for the short, identical provisioning script. Return immediately to ADV_LAB for labs. In organization-managed accounts an authorized administrator must provision equivalent isolated resources per learner; this package's fixed names MUST NOT be used by multiple learners in one account. That alternative has not been authored or tested here.

Run 00-Environment.sql in sections for initial setup or a complete lab reset. It preserves ADV_LAB with CREATE ROLE IF NOT EXISTS, recreates ADV_WH and ADV_ORDERS with CREATE OR REPLACE, reapplies the required grants, and creates four fresh schemas. Each full run removes the previous lab database contents and restores the warehouse settings. After setup, restart from Lab 01. No passwords are embedded and no broad grants are made to PUBLIC.

## Required local Python connection and key setup

The SQL labs and Snowflake-hosted notebooks use the active Snowflake session. The required local Python setup verifies password connectivity, then registers a key pair for local Python connections. Copy the repository-root `.env.example` to `.env` and set `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER` and `SNOWFLAKE_PASSWORD`. The role, warehouse, database, schema and private-key path have classroom defaults in the example. Keep `.env` local; Git ignores it.

Install dependencies with `python -m pip install -r SetUp/requirements.txt`. Run `python SetUp/test_connection.py` and proceed only after it confirms password connectivity. Then run `python SetUp/key_pair_setup.py`; it generates an unencrypted PKCS#8 private key outside the repository, registers its public key by connecting as `ACCOUNTADMIN`, and tests a second connection using the new key pair with the classroom role and context. Both scripts use `python-dotenv` to search upward from the script location for `.env`, so they can be launched from different working directories. The key script refuses to overwrite existing key files. Keep the private key private and never upload or commit it. For production use, encrypting the private key with a passphrase adds protection; the corresponding code option is commented in `key_pair_setup.py`.

Windows is the supported student environment for local Python setup during class. The default key path uses `~` and is intended to resolve to the user's home directory; students using macOS or Linux may need platform-specific help with Python installation, dependency setup or file permissions. Provide that assistance during class as needed; cross-platform setup has not been rehearsed as a required path.

Warehouse auto-suspend limits idle warehouse use; it is not a cap on Snowpipe or total account charges. Monitor classroom consumption and pause ingestion/tasks at day end. Do not promise a fixed lab cost before rehearsal.

Lab 01 creates `ADV_ORDERS.BRONZE.VW_ORDER_EVENTS_SOURCE`, a view over deterministic synthetic mock order-event values with `batch` and `payload` columns. Its payloads are unloaded into staged JSON files for ingestion; it is separate from the Bronze ingestion destination.

## First-class preflight (30 minutes)

Instructor executes; all students repeat: sign in, confirm account/region, execute setup, confirm role and warehouse, execute SELECT 1. Compare outputs. Confirm everyone can create stage, stream, SQL procedure and task. Task owner ADV_LAB needs global EXECUTE TASK plus warehouse USAGE and access to referenced objects. No one proceeds to ingestion until all participants pass.

## Rehearsal and release

A single-account rehearsal completed on 2026-10-12. See the root Validation-report.md for actual coverage and remaining gates. The final warehouse definitions explicitly disable QAS to control inherited account defaults.

On a fresh account execute 00, then Day1 01–06, Day2 07–11 and Day3 13–18, observing every asynchronous pause; run each stop script. Capture account cloud/region, edition, CURRENT_VERSION(), date, role, query IDs, outputs, timings, task history and errors in Validation-report.md. Do not capture credentials. Repeat on a second student-equivalent account. Rehearse another clean run before early November; recheck preview scope and UI changes then. Fix and rerun affected paths before signing off.

## Reset boundaries

Do not reset midway to hide a failed checkpoint. Diagnose the stage, COPY history, inbox and stream first. For a complete rehearsal reset, finish in-flight tasks, run 99, confirm the dedicated training account, then rerun 00-Environment.sql from the beginning. This recreates ADV_WH and ADV_ORDERS and its four schemas while preserving ADV_LAB and the user's authentication configuration. Restart the labs from Lab 01. Never truncate Bronze or recreate a stream while preserving downstream state and call that a replay test.

If a lesson is interrupted, resume at its checkpoint. New worksheets must execute that script's USE statements. Keep identifiers fixed within each dedicated account.

Copyright © 2026 Innovation In Software Corporation. All rights reserved.
