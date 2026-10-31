"""Reusable Snowpark transformations for the Day 1 order-event pipeline.
Copyright © 2026 Innovation In Software Corporation. All rights reserved.
"""
from snowflake.snowpark.functions import (
    col, sql_expr, row_number, when_matched, when_not_matched
)
from snowflake.snowpark.window import Window

ORDER_COLUMNS = ["ORDER_ID", "EVENT_ID", "VERSION", "EVENT_TIME", "STATUS", "AMOUNT", "REGION"]
EVENT_COLUMNS = ["EVENT_ID", "ORDER_ID", "VERSION", "EVENT_TIME", "STATUS", "AMOUNT",
                 "REGION", "REGION_LABEL", "ACTIVE_AMOUNT_USD", "REJECT_REASON",
                 "SOURCE_FILE", "SOURCE_ROW"]

def type_events(df):
    # select_expr builds a DataFrame plan; it does not collect the event rows.
    # Classroom versions use NUMBER(3,1) to keep the displayed values compact.

    return df.select_expr(
        "NULLIF(TRIM(payload:event_id::STRING), '') AS EVENT_ID",
        "NULLIF(TRIM(payload:order_id::STRING), '') AS ORDER_ID",
        "TRY_TO_DECIMAL(payload:version::STRING, 3, 1) AS VERSION",
        "TRY_TO_TIMESTAMP_TZ(payload:event_time::STRING) AS EVENT_TIME",
        "payload:status::STRING AS STATUS",
        "TRY_TO_DECIMAL(payload:amount::STRING, 12, 2) AS AMOUNT",
        "payload:region::STRING AS REGION",
        "SOURCE_FILE", "SOURCE_ROW")

def classify_events(df):
    # Reuse the business rules developed in SQL; express a new DataFrame column.

    return df.with_column("REJECT_REASON",
                          sql_expr("""CASE
                                        WHEN event_id IS NULL OR order_id IS NULL THEN 'MISSING_KEY'
                                        WHEN version IS NULL OR version < 1 OR version <> TRUNC(version) THEN 'BAD_VERSION'
                                        WHEN event_time IS NULL THEN 'BAD_TIME'
                                        WHEN status IS NULL OR status NOT IN ('PLACED', 'PAID', 'CANCELLED') THEN 'BAD_STATUS'
                                        WHEN amount IS NULL OR amount < 0 THEN 'BAD_AMOUNT'
                                        WHEN region IS NULL OR region NOT IN ('US', 'EU') THEN 'BAD_REGION'
                                        ELSE NULL
                                    END"""))

def enrich_events(df_classified, df_reference):
    enriched = df_classified.join(
        df_reference, df_classified["REGION"] == df_reference["REGION_CODE"], "left")
    return enriched.with_column("ACTIVE_AMOUNT_USD", sql_expr("IFF(status = 'CANCELLED', 0, amount)"))

def select_candidates(df):
    good = df.filter(col("REJECT_REASON").is_null())

    # Pick a representative delivery of each immutable event; keep inbox history.
    # File/row identifies delivery lineage, not business-state precedence.

    unique = good.with_column("RN", row_number().over(Window.partition_by("EVENT_ID").order_by(col("SOURCE_FILE"), col("SOURCE_ROW"))))
    unique = unique.filter(col("RN") == 1).drop("RN")

    # Now choose the latest business state using the same SQL precedence rule.

    latest = unique.with_column("RN", row_number().over(Window.partition_by("ORDER_ID").order_by(col("VERSION").desc(), col("EVENT_TIME").desc(), col("EVENT_ID").desc())))
    return latest.filter(col("RN") == 1).select(*ORDER_COLUMNS)

def merge_current(sf_session, df_candidates):
    target = sf_session.table("SILVER.ORDERS_CURRENT")
    newer = (
        (df_candidates["VERSION"] > target["VERSION"])
        | ((df_candidates["VERSION"] == target["VERSION"])
           & (df_candidates["EVENT_TIME"] > target["EVENT_TIME"]))
        | ((df_candidates["VERSION"] == target["VERSION"])
           & (df_candidates["EVENT_TIME"] == target["EVENT_TIME"])
           & (df_candidates["EVENT_ID"] > target["EVENT_ID"]))
    )
    updates = {name: df_candidates[name] for name in ORDER_COLUMNS if name != "ORDER_ID"}
    inserts = {name: df_candidates[name] for name in ORDER_COLUMNS}

    # Table.merge is an action: Snowflake executes MERGE and returns row counts.

    return target.merge(df_candidates, target["ORDER_ID"] == df_candidates["ORDER_ID"], [
        when_matched(newer).update(updates),
        when_not_matched().insert(inserts)
    ])

def main(sf_session):
    # Only SQL transaction control and stream capture remain sf_session.sql calls.
    # All destinations already exist; no DDL belongs inside this transaction.

    sf_session.sql("BEGIN TRANSACTION").collect()
    try:
        # Consume this stream into the inbox ONCE per transaction.

        sf_session.sql("""INSERT INTO SILVER.EVENT_INBOX
            SELECT payload, source_file, source_row, scan_time
            FROM BRONZE.EVENTS_STREAM""").collect()
        if sf_session.table("SILVER.EVENT_CONFLICTS").count():
            raise ValueError("Conflicting payloads for immutable event_id")

        typed = type_events(sf_session.table("SILVER.EVENT_INBOX"))
        classified = classify_events(typed)
        enriched = enrich_events(classified, sf_session.table("SILVER.REGION_REFERENCE"))
        candidates = select_candidates(enriched)

        sf_session.table("SILVER.SNOWPARK_EVENTS").delete()
        enriched.select(*EVENT_COLUMNS).write.insert_into("SILVER.SNOWPARK_EVENTS")
        sf_session.table("SILVER.SNOWPARK_CANDIDATES").delete()
        candidates.write.insert_into("SILVER.SNOWPARK_CANDIDATES")
        result = merge_current(sf_session, sf_session.table("SILVER.SNOWPARK_CANDIDATES"))
        sf_session.sql("COMMIT").collect()
        return f"Applied with Snowpark: {result}"
    except Exception:
        sf_session.sql("ROLLBACK").collect()
        raise
