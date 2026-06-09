#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_DIR/.env"

start_port_forward() {
    local name="$1"
    local namespace="$2"
    local service="$3"
    local local_port="$4"
    local remote_port="$5"

    if lsof -i "TCP:$local_port" >/dev/null 2>&1; then
        echo "Port $local_port is already in use. Assuming $name port-forward is running."
        return 0
    fi

    if ! kubectl get "svc/$service" -n "$namespace" >/dev/null 2>&1; then
        echo "$name service not found in namespace $namespace. Skipping port-forward."
        return 1
    fi

    echo "Starting port-forward for $name on port $local_port..."
    nohup kubectl --namespace "$namespace" port-forward "svc/$service" "$local_port:$remote_port" >/dev/null 2>&1 &
}

echo "Setting up port-forwards..."

start_port_forward "Backstage" "$BACKSTAGE_NAMESPACE" "backstage" "$BACKSTAGE_PORT" "80"
start_port_forward "LocalStack" "$LOCALSTACK_NAMESPACE" "localstack" "$LOCALSTACK_PORT" "$LOCALSTACK_PORT"
start_port_forward "Crossview" "$CROSSVIEW_NAMESPACE" "crossview" "$CROSSVIEW_PORT" "3001"

echo "Port-forwards started successfully!"
