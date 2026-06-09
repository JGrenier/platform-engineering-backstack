#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/.env"

if [[ "$(kubectl config current-context)" != "$K8S_LOCAL_CONTEXT_NAME" ]]; then
    kubectl config use-context "$K8S_LOCAL_CONTEXT_NAME" || {
        echo "Failed to switch context to $K8S_LOCAL_CONTEXT_NAME"
        exit 1
    }
fi

NS=argocd
PORT=8080

# NS="$ARGOCD_NAMESPACE"
MANIFESTS_DIR="$SCRIPT_DIR/manifests"
# PORT="$ARGOCD_PORT"

echo "Adding Argo CD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update

echo "Installing or upgrading Argo CD..."
helm upgrade --install argocd \
    --namespace "$NS" \
    --create-namespace argo/argo-cd

echo "Waiting for Argo CD deployment to be ready..."
kubectl wait --for=condition=available --timeout=240s deployment/argocd-server -n "$NS" || {
    echo "Argo CD deployment is not ready"
    exit 1
}

kubectl patch configmap argocd-cm -n "$NS" --patch-file "$MANIFESTS_DIR/argocd-cm-patch.yaml"
kubectl patch deploy argocd-server -n "$NS" --patch-file "$MANIFESTS_DIR/deployment.yaml"
kubectl patch svc argocd-server -n "$NS" --patch-file "$MANIFESTS_DIR/service.yaml"
kubectl rollout restart deployment argocd-server -n "$NS"
kubectl rollout status deployment argocd-server -n "$NS"

if ! lsof -i "TCP:$PORT" >/dev/null 2>&1; then
    if kubectl get svc/argocd-server -n "$NS" >/dev/null 2>&1; then
        echo "Starting port-forward for Argo CD on port $PORT..."
        nohup kubectl --namespace "$NS" port-forward svc/argocd-server "$PORT:443" >/dev/null 2>&1 &
    else
        echo "Argo CD service not found. Skipping port-forward."
        exit 1
    fi
else
    echo "Port $PORT is already in use. Assuming port-forward is running."
fi

sleep 5

INITIAL_PASSWORD=$(kubectl -n "$NS" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "Attempting Argo CD login..."
if argocd login "localhost:$PORT" --username admin --password "$INITIAL_PASSWORD" --insecure >/dev/null 2>&1; then
    echo "Logged in using initial password."
    echo "Updating Argo CD admin password..."
    argocd account update-password --account admin --current-password "$INITIAL_PASSWORD" --new-password "$ARGOCD_PWD"
elif argocd login "localhost:$PORT" --username admin --password "$ARGOCD_PWD" --insecure >/dev/null 2>&1; then
    echo "Already using the updated password. Login succeeded."
else
    echo "Failed to login with both initial and updated password. Aborting."
    exit 1
fi

if ! argocd repo list | grep -q "$ARGOCD_REPO_URL"; then
    echo "Adding Git repo to Argo CD..."
    # argocd repo add "$ARGOCD_REPO_URL" --ssh-private-key-path "$SSH_PRIVATE_KEY_PATH"
    argocd repo add "git@github.com:JGrenier/platform-engineering-backstack.git" --ssh-private-key-path ~/.ssh/id_ed25519
else
    echo "Git repo already added."
fi

if ! argocd cluster list | grep -q "$K8S_LOCAL_CONTEXT_NAME"; then
    echo "Registering $K8S_LOCAL_CONTEXT_NAME cluster to Argo CD..."
    argocd cluster add "$K8S_LOCAL_CONTEXT_NAME" --insecure --in-cluster -y
else
    echo "Cluster $K8S_LOCAL_CONTEXT_NAME already registered."
fi

echo "Applying Argo CD manifests..."
envsubst < "$PROJECT_DIR/argocd/apps.yaml" | kubectl apply -f -
envsubst < "$PROJECT_DIR/argocd/crossplane-system.yaml" | kubectl apply -f -

echo "Argo CD setup completed successfully!"
