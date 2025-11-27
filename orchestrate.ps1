# Orchestration script for Ex2ToAmDebezPoC Podman group
# This script sets up Kafka, init Kafka, and Debezium containers

$ErrorActionPreference = "Stop"

Write-Host "Starting orchestration for Ex2ToAmDebezPoC..." -ForegroundColor Green

# Podman group name
$PODMAN_GROUP = "Ex2ToAmDebezPoC"

# Network name
$NETWORK_NAME = "debezium-network"

# Container names
$KAFKA_CONTAINER = "kafka"
$INIT_KAFKA_CONTAINER = "init-kafka"
$DEBEZIUM_CONTAINER = "debezium-connect"

# Check if podman group exists, create if not
Write-Host "Checking podman group..." -ForegroundColor Yellow
$groupExists = podman pod exists $PODMAN_GROUP 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating podman pod: $PODMAN_GROUP" -ForegroundColor Yellow
    podman pod create --name $PODMAN_GROUP -p 9092:9092 -p 8083:8083 -p 8080:8080
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create podman pod" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Podman pod already exists" -ForegroundColor Yellow
}

# Create network if it doesn't exist
Write-Host "Checking network..." -ForegroundColor Yellow
$networkExists = podman network exists $NETWORK_NAME 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating network: $NETWORK_NAME" -ForegroundColor Yellow
    podman network create $NETWORK_NAME
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create network" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Network already exists" -ForegroundColor Yellow
}

# Start Zookeeper (required for Kafka)
Write-Host "Starting Zookeeper..." -ForegroundColor Yellow
$zookeeperExists = podman container exists zookeeper 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Zookeeper container exists, removing to ensure clean configuration..." -ForegroundColor Yellow
    podman rm -f zookeeper
}

podman run -d `
    --name zookeeper `
    --pod $PODMAN_GROUP `
    --network $NETWORK_NAME `
    -e ZOOKEEPER_CLIENT_PORT=2181 `
    -e ZOOKEEPER_TICK_TIME=2000 `
    -e ZOOKEEPER_INIT_LIMIT=5 `
    -e ZOOKEEPER_SYNC_LIMIT=2 `
    confluentinc/cp-zookeeper:latest

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start Zookeeper" -ForegroundColor Red
    exit 1
}

Write-Host "Waiting for Zookeeper to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Verify Zookeeper is responding
$maxRetries = 10
$retryCount = 0
$zookeeperReady = $false

while ($retryCount -lt $maxRetries -and -not $zookeeperReady) {
    try {
        $result = podman exec zookeeper bash -c "echo ruok | nc localhost 2181" 2>$null
        if ($result -eq "imok") {
            $zookeeperReady = $true
        }
    } catch {
        # Continue retrying
    }
    if (-not $zookeeperReady) {
        $retryCount++
        Start-Sleep -Seconds 2
    }
}

if (-not $zookeeperReady) {
    Write-Host "Warning: Zookeeper may not be fully ready, but continuing..." -ForegroundColor Yellow
} else {
    Write-Host "Zookeeper is ready" -ForegroundColor Green
}

# Start Kafka
Write-Host "Starting Kafka..." -ForegroundColor Yellow
$kafkaExists = podman container exists $KAFKA_CONTAINER 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Kafka container exists, removing to ensure clean configuration..." -ForegroundColor Yellow
    podman rm -f $KAFKA_CONTAINER
}

podman run -d `
    --name $KAFKA_CONTAINER `
    --pod $PODMAN_GROUP `
    --network $NETWORK_NAME `
    -e KAFKA_BROKER_ID=1 `
    -e KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181 `
    -e KAFKA_ZOOKEEPER_SESSION_TIMEOUT_MS=18000 `
    -e KAFKA_ZOOKEEPER_CONNECTION_TIMEOUT_MS=18000 `
    -e KAFKA_ZOOKEEPER_REQUEST_TIMEOUT_MS=30000 `
    -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://localhost:9092 `
    -e KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092 `
    -e KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT `
    -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 `
    -e KAFKA_AUTO_CREATE_TOPICS_ENABLE=true `
    -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 `
    -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 `
    confluentinc/cp-kafka:7.4.0

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start Kafka" -ForegroundColor Red
    exit 1
}
Write-Host "Waiting for Kafka to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Start init Kafka container to create topic
Write-Host "Creating init Kafka container to create 'ex2-am' topic..." -ForegroundColor Yellow
$initKafkaExists = podman container exists $INIT_KAFKA_CONTAINER 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Removing existing init-kafka container..." -ForegroundColor Yellow
    podman rm -f $INIT_KAFKA_CONTAINER
}

podman run --rm `
    --name $INIT_KAFKA_CONTAINER `
    --pod $PODMAN_GROUP `
    --network $NETWORK_NAME `
    -e KAFKA_BOOTSTRAP_SERVERS=localhost:9092 `
    confluentinc/cp-kafka:7.4.0 `
    kafka-topics --create `
    --if-not-exists `
    --bootstrap-server localhost:9092 `
    --replication-factor 1 `
    --partitions 1 `
    --topic ex2-am

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to create topic 'ex2-am'" -ForegroundColor Red
    exit 1
}

Write-Host "Topic 'ex2-am' created successfully" -ForegroundColor Green

# Start Kafka UI (optional but helpful for monitoring)
Write-Host "Starting Kafka UI..." -ForegroundColor Yellow
$kafkaUIExists = podman container exists kafka-ui 2>$null
if ($LASTEXITCODE -ne 0) {
    podman run -d `
        --name kafka-ui `
        --pod $PODMAN_GROUP `
        --network $NETWORK_NAME `
        -e KAFKA_CLUSTERS_0_NAME=local `
        -e KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS=localhost:9092 `
        provectuslabs/kafka-ui:latest
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to start Kafka UI" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Kafka UI already exists, starting..." -ForegroundColor Yellow
    podman start kafka-ui
}

# Start Debezium Connect
Write-Host "Starting Debezium Connect..." -ForegroundColor Yellow
$debeziumExists = podman container exists $DEBEZIUM_CONTAINER 2>$null
if ($LASTEXITCODE -ne 0) {
    # Create Debezium configuration
    # Note: Table name "TestOutboxes" has quotes for case sensitivity in PostgreSQL
    $debeziumConfig = @{
        "name" = "ex2-am-connector"
        "config" = @{
            "connector.class" = "io.debezium.connector.postgresql.PostgresConnector"
            "database.hostname" = "host.docker.internal"
            "database.port" = "5433"
            "database.user" = "admin"
            "database.password" = "admin123"
            "database.dbname" = "ex2_outbox_demo_response_save"
            "database.server.name" = "ex2-am-server"
            "table.include.list" = 'ex2_outbox_demo_response_save."TestOutboxes"'
            "topic.prefix" = "ex2-am"
            "plugin.name" = "pgoutput"
            "slot.name" = "debezium_slot"
            "publication.name" = "debezium_pub"
            "publication.autocreate.mode" = "filtered"
            "transforms" = "route"
            "transforms.route.type" = "org.apache.kafka.connect.transforms.RegexRouter"
            "transforms.route.regex" = 'ex2-am-server.ex2_outbox_demo_response_save."TestOutboxes"'
            "transforms.route.replacement" = "ex2-am"
        }
    }

    # For Podman on Windows, we may need to add --add-host to access host machine
    # Alternatively, use the gateway IP if host.docker.internal doesn't work
    podman run -d `
        --name $DEBEZIUM_CONTAINER `
        --pod $PODMAN_GROUP `
        --network $NETWORK_NAME `
        --add-host=host.docker.internal:host-gateway `
        -e GROUP_ID=1 `
        -e CONFIG_STORAGE_TOPIC=my_connect_configs `
        -e OFFSET_STORAGE_TOPIC=my_connect_offsets `
        -e STATUS_STORAGE_TOPIC=my_connect_statuses `
        -e BOOTSTRAP_SERVERS=localhost:9092 `
        -e CONNECT_REST_ADVERTISED_HOST_NAME=localhost `
        debezium/connect:latest

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to start Debezium Connect" -ForegroundColor Red
        exit 1
    }

    Write-Host "Waiting for Debezium Connect to be ready..." -ForegroundColor Yellow
    $maxRetries = 30
    $retryCount = 0
    $isReady = $false
    
    while ($retryCount -lt $maxRetries -and -not $isReady) {
        try {
            $healthCheck = Invoke-RestMethod -Uri "http://localhost:8083" -Method Get -ErrorAction SilentlyContinue
            $isReady = $true
        } catch {
            $retryCount++
            Start-Sleep -Seconds 2
        }
    }
    
    if (-not $isReady) {
        Write-Host "Warning: Debezium Connect may not be fully ready, but continuing..." -ForegroundColor Yellow
    }

    # Check if connector already exists
    Write-Host "Checking if connector already exists..." -ForegroundColor Yellow
    try {
        $existingConnector = Invoke-RestMethod -Uri "http://localhost:8083/connectors/ex2-am-connector" -Method Get -ErrorAction Stop
        if ($existingConnector) {
            Write-Host "Connector already exists, updating..." -ForegroundColor Yellow
            $configJson = $debeziumConfig.config | ConvertTo-Json -Depth 10
            $response = Invoke-RestMethod -Uri "http://localhost:8083/connectors/ex2-am-connector/config" -Method Put -ContentType "application/json" -Body $configJson
            Write-Host "Connector updated: ex2-am-connector" -ForegroundColor Green
        }
    } catch {
        # Connector doesn't exist, create it
        Write-Host "Registering new Debezium connector..." -ForegroundColor Yellow
        try {
            $connectorJson = $debeziumConfig | ConvertTo-Json -Depth 10
            $response = Invoke-RestMethod -Uri "http://localhost:8083/connectors" -Method Post -ContentType "application/json" -Body $connectorJson
            Write-Host "Connector registered: $($response.name)" -ForegroundColor Green
        } catch {
            Write-Host "Failed to register connector: $_" -ForegroundColor Red
            Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "You may need to register it manually via: http://localhost:8083/connectors" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "Debezium Connect already exists, starting..." -ForegroundColor Yellow
    podman start $DEBEZIUM_CONTAINER
    Start-Sleep -Seconds 10
}

Write-Host "`nOrchestration completed successfully!" -ForegroundColor Green
Write-Host "Services available at:" -ForegroundColor Cyan
Write-Host "  - Kafka: localhost:9092" -ForegroundColor Cyan
Write-Host "  - Kafka UI: http://localhost:8080" -ForegroundColor Cyan
Write-Host "  - Debezium Connect API: http://localhost:8083" -ForegroundColor Cyan
Write-Host "`nMonitor the 'ex2-am' topic in Kafka UI to see Debezium events" -ForegroundColor Yellow

