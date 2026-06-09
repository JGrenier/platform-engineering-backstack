#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_DIR/.env"

APPS=("apps" "backstage-app" "crossplane-app" "localstack-app" "crossview-app" "kyverno-app" "kyverno-policies")
TIMEOUT=600

echo "Waiting for all ArgoCD applications to become healthy (timeout: ${TIMEOUT}s)..."

for app in "${APPS[@]}"; do
    echo "Waiting for '$app'..."
    if ! argocd app wait "$app" --health --timeout "$TIMEOUT" 2>/dev/null; then
        echo "Warning: '$app' did not become healthy within timeout. Continuing..."
    else
        echo "'$app' is healthy."
    fi
done

echo "All ArgoCD applications checked!"
