
include .env
export

.PHONY: up down check_bins build-backstage setup-local-config

check_bins:
	@command -v kind >/dev/null 2>&1 || { echo >&2 "kind not found! Please install it before continuing."; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl not found! Please install it before continuing."; exit 1; }
	@command -v argocd >/dev/null 2>&1 || { echo >&2 "argocd not found! Please install it before continuing."; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo >&2 "helm not found! Please install it before continuing."; exit 1; }
	@command -v yq >/dev/null 2>&1 || { echo >&2 "yq not found! Please install it before continuing."; exit 1; }
	@YQ_VERSION=$$(yq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
	if [ -n "$$YQ_VERSION" ]; then \
		YQ_MAJOR=$$(echo $$YQ_VERSION | cut -d. -f1); \
		YQ_MINOR=$$(echo $$YQ_VERSION | cut -d. -f2); \
		YQ_PATCH=$$(echo $$YQ_VERSION | cut -d. -f3); \
		if [ $$YQ_MAJOR -lt 4 ] || ([ $$YQ_MAJOR -eq 4 ] && [ $$YQ_MINOR -lt 45 ]) || ([ $$YQ_MAJOR -eq 4 ] && [ $$YQ_MINOR -eq 45 ] && [ $$YQ_PATCH -lt 1 ]); then \
			echo >&2 "yq version $$YQ_VERSION is too old! Please install version v4.45.1 or higher."; \
			exit 1; \
		fi; \
	else \
		echo >&2 "Could not determine yq version! Please ensure yq v4.45.1 or higher is installed."; \
		exit 1; \
	fi

build-backstage:
	@echo "Building Backstage image..."
	@if docker image inspect $(BACKSTAGE_IMAGE) >/dev/null 2>&1; then \
		echo "Docker image $(BACKSTAGE_IMAGE) already exists. Skipping build."; \
	else \
		cd ./backstage && yarn install && yarn build:all && yarn build-image --tag $(BACKSTAGE_IMAGE) --no-cache && cd ..; \
	fi
	@echo "Loading Backstage image into kind cluster..."
	@kind load docker-image $(BACKSTAGE_IMAGE) --name $(K8S_CLUSTER_NAME)

up: check_bins
	@echo "=== Phase 1: Cluster + ArgoCD (imperative) ==="
	@if kind get clusters | grep -q "^$(K8S_CLUSTER_NAME)$$"; then \
		echo "Cluster '$(K8S_CLUSTER_NAME)' already exists. Skipping..."; \
	else \
		kind create cluster --name $(K8S_CLUSTER_NAME); \
	fi

	@$(MAKE) build-backstage

	@./.bootstrap/argocd/up.sh

	@echo "=== Phase 1b: Secrets (before ArgoCD sync) ==="
	@./.bootstrap/create-secrets.sh

	@echo "=== Phase 2: ArgoCD declarative sync ==="
	@./.bootstrap/wait-for-sync.sh

	@echo "=== Phase 3: Post-sync setup ==="
	@./.bootstrap/port-forward.sh
	@$(MAKE) setup-local-config

	@echo
	@echo "---------------------------------------------------------------------------------------------------------------------------"
	@echo "Backstage is accessible at http://localhost:$(BACKSTAGE_PORT)"
	@echo "Argo CD is accessible at http://localhost:$(ARGOCD_PORT)"
	@echo "Crossview is accessible at http://localhost:$(CROSSVIEW_PORT)"
	@echo "LocalStack is accessible at http://localhost:$(LOCALSTACK_PORT) (Manage through the platform at: https://app.localstack.cloud/instances)"

down: check_bins
	@echo "Deleting environment..."
	@if kind get clusters | grep -q "^$(K8S_CLUSTER_NAME)$$"; then \
		kind delete cluster --name $(K8S_CLUSTER_NAME); \
	else \
		echo "Cluster '$(K8S_CLUSTER_NAME)' not found. Skipping..."; \
	fi

setup-local-config: check_bins
	@echo "Updating app-config.local.yaml..."
	@test -f backstage/app-config.local.yaml || echo "{}" > backstage/app-config.local.yaml
	@export SERVICE_ACCOUNT_TOKEN=$$(kubectl get secret -n $(BACKSTAGE_NAMESPACE) backstage-token -o jsonpath='{.data.token}' | base64 --decode); \
	export CLUSTER_URL=$$(kubectl cluster-info | grep 'Kubernetes control plane' | awk '{print $$NF}'); \
	FILE="backstage/app-config.local.yaml"; \
	yq -i '.kubernetes.clusterLocatorMethods[0].clusters[0].serviceAccountToken = strenv(SERVICE_ACCOUNT_TOKEN)' $$FILE; \
	yq -i '.kubernetes.clusterLocatorMethods[0].clusters[0].url = strenv(CLUSTER_URL)' $$FILE
