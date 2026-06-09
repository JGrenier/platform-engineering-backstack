#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_DIR/.env"

echo "Creating namespaces..."
kubectl create ns "$BACKSTAGE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns "$CROSSPLANE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Applying Backstage secrets..."
export GITHUB_TOKEN_B64
GITHUB_TOKEN_B64=$(echo -n "$GITHUB_TOKEN" | base64)
envsubst < "$SCRIPT_DIR/backstage/manifests/secrets.yaml" | kubectl apply -n "$BACKSTAGE_NAMESPACE" -f -

echo "Creating Crossplane AWS (LocalStack) secret..."
kubectl create secret generic aws-secret -n "$CROSSPLANE_NAMESPACE" \
    --from-file=creds="$SCRIPT_DIR/crossplane/manifests/aws-credentials.txt" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets created successfully!"
