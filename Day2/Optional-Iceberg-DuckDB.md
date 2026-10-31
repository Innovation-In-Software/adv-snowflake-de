# Optional Iceberg / DuckDB interoperability — rehearsal gate

This branch is not a ready-to-run student lab until the checklist below passes. The route is DuckDB reading a prepared Snowflake-managed Iceberg table through Snowflake Horizon Iceberg REST Catalog. Do not confuse it with Snowflake consuming a third-party catalog through a catalog integration.

## Required shared preparation

1. Use a dedicated approved external volume and storage location. Confirm Snowflake and the external reader's storage permissions and credential delegation.
2. Create a small synthetic Iceberg table using SQL in every account, or explicitly classify this as a demonstration. Record the external volume, base location, catalog endpoint and warehouse/catalog mapping; do not insert guessed endpoints into the lab.
3. Enable and grant the documented Horizon catalog access for the participant role. Prepare an allowed authentication mechanism, such as a supported scoped programmatic access token. Never commit tokens or copy them onto slides.
4. Install and record the exact DuckDB and Iceberg extension versions on the student machine. Loading an extension can require network access. No instructor-only Python utility may hide setup.
5. Execute the documented DuckDB secret/catalog attachment appropriate to the pinned version and endpoint. The syntax and Snowflake authentication mapping must be rehearsed together; a generic REST example is insufficient.
6. Read the same snapshot through Snowflake SQL and DuckDB; compare row count, order keys and USD aggregate. Record snapshot identifier and query time. Keep the exercise read-only.
7. Test a denied role and revoke the temporary credential after the session.

## Go / no-go evidence

Record account/cloud, supported edition, table/catalog type, table format version, external volume, endpoint, credential delegation mode, reader version, successful attachment, matching snapshot and result comparison. Stop if any item is unresolved. Do not claim interoperability passed from SHOW ICEBERG TABLES alone.

Expected duration after rehearsal: 20–30 minutes. Skip this branch without disrupting the core Bronze/Silver/Gold project if storage or authentication is unavailable.

## Authoritative references

- Snowflake Horizon external engine access: https://docs.snowflake.com/en/user-guide/tables-iceberg-access-using-external-query-engine-snowflake-horizon
- DuckDB Iceberg extension: https://duckdb.org/docs/stable/core_extensions/iceberg/overview
- DuckDB REST catalog documentation (verify the documented version): https://duckdb.org/docs/stable/core_extensions/iceberg/iceberg_rest_catalogs

There is intentionally no invented connection command or embedded credential in this file. A final account-specific connection example is a remaining deliverable after the checklist has been validated.

Copyright © 2026 Innovation In Software Corporation. All rights reserved.
