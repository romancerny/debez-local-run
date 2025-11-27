# Ex2ToAmDebezPoC - Debezium Setup Scripts

This project contains PowerShell scripts to orchestrate and tear down a local Podman-based Debezium setup for capturing PostgreSQL change events.

## Prerequisites

- Podman installed and running
- PostgreSQL database running on `localhost:5433` with:
  - Database: `ex2_outbox_demo_response_save`
  - Username: `admin`
  - Password: `admin123`
  - Table: `"TestOutboxes"` (case-sensitive, quoted identifier)
- PostgreSQL must have logical replication enabled (`wal_level = logical`)
- The `pgoutput` plugin must be available

## Scripts

### orchestrate.ps1

Orchestrates the following containers in a Podman pod named `Ex2ToAmDebezPoC`:

1. **Zookeeper** - Required for Kafka coordination
2. **Kafka** - Message broker on port 9092
3. **Init Kafka Container** - Creates the `ex2-am` topic
4. **Kafka UI** - Web interface for monitoring Kafka (http://localhost:8080)
5. **Debezium Connect** - Captures PostgreSQL changes and publishes to Kafka

The Debezium connector is configured to:
- Connect to PostgreSQL at `localhost:5433`
- Monitor the `ex2_outbox_demo_response_save."TestOutboxes"` table
- Publish events to the `ex2-am` topic in Kafka

### teardown.ps1

Removes all containers, the pod, and network created by the orchestration script.

## Usage

### Start the setup:

```powershell
.\orchestrate.ps1
```

### Stop and clean up:

```powershell
.\teardown.ps1
```

## Monitoring

After running `orchestrate.ps1`, you can:

1. **View Kafka topics and messages** in Kafka UI: http://localhost:8080
2. **Check Debezium connector status** via REST API: http://localhost:8083/connectors/ex2-am-connector
3. **View connector logs**: `podman logs debezium-connect`

## Testing

To test the setup:

1. Insert or update a row in the `ex2_outbox_demo_response_save."TestOutboxes"` table
2. Check the `ex2-am` topic in Kafka UI to see the Debezium change event

## Troubleshooting

### Debezium cannot connect to PostgreSQL

- Ensure PostgreSQL is running and accessible from the host
- For Podman on Windows, the `--add-host=host.docker.internal:host-gateway` flag is used
- Verify the connection string credentials are correct

### Connector registration fails

- Check Debezium Connect logs: `podman logs debezium-connect`
- Verify Kafka is running: `podman logs kafka`
- Manually register the connector via REST API if needed

### No events appearing in Kafka

- Verify the table name matches exactly (case-sensitive): `"TestOutboxes"`
- Check PostgreSQL logical replication is enabled
- Verify the `pgoutput` plugin is available
- Check Debezium connector status for errors

