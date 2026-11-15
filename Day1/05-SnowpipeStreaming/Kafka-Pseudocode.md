# Kafka to Snowpipe Streaming: teaching pseudocode

**Discussion only — not runnable Python.** The methods below illustrate responsibilities, not exact Kafka or Snowflake SDK APIs. No Kafka installation is required for Lab 05.

Normally, use the **Snowflake Connector for Kafka**, running in Kafka Connect. It provides the integration instead of requiring students to build a consumer and recovery logic.

## Connect this to the lab

In `stream_rows.py`, the loop `for number in range(1, 4)` generates three sample events. A custom Kafka application would get its events from Kafka instead.

```text
Kafka topic → Kafka consumer → custom application → Streaming SDK → Snowflake
```

- A **topic** is a named event stream, such as `order_events`.
- A **partition** is one ordered log within that topic. Partitions allow parallel processing; there is no global ordering across partitions.
- An **offset** identifies a record's position within one partition. Offsets are not necessarily consecutive.
- The **consumer** is the Kafka client that reads records and tracks source progress.
- The **channel** is the Snowpipe Streaming destination used to append records and track committed ingestion progress.

For this conceptual design, map each topic partition to a stable channel. Unlike the lab's new channel on every run, a stable identity allows recovery after a restart.

## Illustrative pseudocode

```python
# NOT RUNNABLE: conceptual operations, not actual SDK method signatures.
# Repeat this flow independently for each assigned Kafka partition.
# Only one active writer owns this channel at a time.

channel = open_stable_channel(topic, partition)

# Snowflake's committed progress determines what has reached the destination.
last_committed = channel.get_committed_offset()

if last_committed is not None:
    consumer.seek(partition, int(last_committed) + 1)
else:
    # Explicit policy: for example, earliest retained record or a checkpoint
    # established when creating this new destination. Do not guess on recovery.
    consumer.seek(partition, configured_start_offset)

# Kafka automatic offset commits must be disabled for this design.
while running_and_partition_still_owned:
    records = consumer.poll(partition)

    if not records:
        continue

    for record in records:
        channel.append_row(
            row=convert_to_snowflake_row(record.value),
            offset_token=str(record.offset),
        )

    last_sent = records[-1].offset

    # Appending is not proof of a committed write.
    channel.wait_for_commit(
        lambda token: token is not None and int(token) >= last_sent
    )

    # Kafka records the NEXT offset to consume, not the last processed offset.
    # Commit only after Snowflake confirms the corresponding ingestion.
    consumer.commit(partition, next_offset=last_sent + 1)
```

Here, `lambda` is a Python anonymous function that checks committed progress. It is **not AWS Lambda** and does not control batching. The Streaming SDK handles buffering and transmission.

## Explain the recovery boundary

If the application stops after Snowflake commits but before Kafka progress is saved, it can recover using the stable channel's committed offset. Reading a Kafka message alone does not prove that Snowflake has stored it.

This is not a complete production design. Production code must handle partition assignment/revocation, exclusive channel ownership, Kafka polling/heartbeat requirements, backpressure, rejected records, timeouts, retries, retention gaps, and shutdown. A failed or rejected row must not be silently skipped by advancing progress past it. A timeout does not prove that ingestion failed.

Offset tracking does not remove duplicate business events published at different Kafka offsets. The lab itself deliberately adds another three rows on each run and does not implement restart recovery.

## Suggested classroom explanation

> Our loop generates three events. In a Kafka application, a consumer supplies the events and their partition offsets. Snowpipe Streaming appends them to Snowflake, and we wait for committed progress before acknowledging consumption. In production, we normally use the Snowflake Connector for Kafka to manage this integration.

References: [Snowflake Connector for Kafka](https://docs.snowflake.com/en/user-guide/kafka-connector/index) and [how the connector works](https://docs.snowflake.com/en/user-guide/kafka-connector/how-the-connector-works).
