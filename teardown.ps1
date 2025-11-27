# Teardown script for Ex2ToAmDebezPoC Podman group
# This script removes all containers and cleans up resources

$ErrorActionPreference = "Stop"

Write-Host "Starting teardown for Ex2ToAmDebezPoC..." -ForegroundColor Yellow

# Podman group name
$PODMAN_GROUP = "Ex2ToAmDebezPoC"

# Network name
$NETWORK_NAME = "debezium-network"

# Container names
$KAFKA_CONTAINER = "kafka"
$INIT_KAFKA_CONTAINER = "init-kafka"
$DEBEZIUM_CONTAINER = "debezium-connect"
$ZOOKEEPER_CONTAINER = "zookeeper"
$KAFKA_UI_CONTAINER = "kafka-ui"

# Stop and remove containers
Write-Host "Stopping and removing containers..." -ForegroundColor Yellow

$containers = @($KAFKA_CONTAINER, $DEBEZIUM_CONTAINER, $ZOOKEEPER_CONTAINER, $KAFKA_UI_CONTAINER, $INIT_KAFKA_CONTAINER)

foreach ($container in $containers) {
    $exists = podman container exists $container 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Removing container: $container" -ForegroundColor Yellow
        podman rm -f $container 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Removed: $container" -ForegroundColor Green
        }
    } else {
        Write-Host "  Container not found: $container" -ForegroundColor Gray
    }
}

# Remove podman pod
Write-Host "Removing podman pod: $PODMAN_GROUP" -ForegroundColor Yellow
$podExists = podman pod exists $PODMAN_GROUP 2>$null
if ($LASTEXITCODE -eq 0) {
    podman pod rm -f $PODMAN_GROUP
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Removed pod: $PODMAN_GROUP" -ForegroundColor Green
    }
} else {
    Write-Host "  Pod not found: $PODMAN_GROUP" -ForegroundColor Gray
}

# Remove network (optional - only if no other containers are using it)
Write-Host "Removing network: $NETWORK_NAME" -ForegroundColor Yellow
$networkExists = podman network exists $NETWORK_NAME 2>$null
if ($LASTEXITCODE -eq 0) {
    podman network rm $NETWORK_NAME 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Removed network: $NETWORK_NAME" -ForegroundColor Green
    } else {
        Write-Host "  Network may be in use by other containers, skipping removal" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Network not found: $NETWORK_NAME" -ForegroundColor Gray
}

Write-Host "`nTeardown completed!" -ForegroundColor Green

