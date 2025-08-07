# Complete Helm Guide: Understanding How Helm Works and Enterprise Deployment

This comprehensive guide explains how Helm works step-by-step, corrects common misconceptions, and provides a complete understanding for enterprise deployments with local artifacts.

## Table of Contents

1. [What is Helm?](#what-is-helm)
2. [How Helm Works - Step by Step](#how-helm-works---step-by-step)
3. [Understanding Your Current Setup](#understanding-your-current-setup)
4. [Helm Architecture Deep Dive](#helm-architecture-deep-dive)
5. [Enterprise Setup: Local Artifacts Only](#enterprise-setup-local-artifacts-only)
6. [Complete Enterprise Deployment Guide](#complete-enterprise-deployment-guide)
7. [Troubleshooting and Best Practices](#troubleshooting-and-best-practices)

## What is Helm?

Helm is a **package manager for Kubernetes** - think of it like `apt` for Ubuntu, `yum` for RedHat, or `npm` for Node.js, but for Kubernetes applications.

### Key Concepts:

- **Chart**: A collection of Kubernetes YAML templates packaged together
- **Release**: An instance of a chart running in your cluster
- **Repository**: A place where charts are stored (like Docker Hub for images)
- **Values**: Configuration parameters that customize how a chart is deployed

## How Helm Works - Step by Step

Let me correct and clarify your understanding:

### Step 1: Prerequisites Setup ✅

```bash
# 1. Install kubectl (Kubernetes CLI) - YES, you need this
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"

# 2. Install Helm (the package manager)
brew install helm
# OR
curl https://get.helm.sh/helm-v3.12.0-darwin-amd64.tar.gz | tar xz

# 3. Configure kubectl to connect to your cluster
aws eks update-kubeconfig --region us-east-1 --name your-cluster-name
```

**Your Understanding**: ✅ Correct - You need kubectl, Helm, and cluster access

### Step 2: Understanding Helm Repositories ✅

```bash
# Add a Helm repository (like adding a package source)
helm repo add flyteorg https://flyteorg.github.io/flyte
helm repo update
```

**What this does:**
- Tells Helm where to find charts (like `apt` sources)
- Downloads the repository index
- **You don't download the actual charts yet**

**Your Understanding**: ✅ Mostly correct - but you're not downloading files yet, just registering where to find them

### Step 3: Understanding Values Files 🔍

**Your Question**: "What are these values and how do we know their contents?"

Values files configure how the application deploys. There are several ways to understand what values are available:

```bash
# Method 1: Get default values from the chart
helm show values flyteorg/flyte-binary > default-values.yaml

# Method 2: Get the entire chart definition
helm pull flyteorg/flyte-binary --untar
# This downloads the complete chart with all templates to ./flyte-binary/

# Method 3: Check documentation
helm show readme flyteorg/flyte-binary
```

**What's in values.yaml:**
- Database connection settings
- Storage configuration (S3, GCS, etc.)
- Resource limits (CPU, memory)
- Image tags and repositories
- Feature toggles
- Security settings

### Step 4: Understanding Chart Templates 📋

**Your Question**: "How do I get all the deployment and service definitions locally?"

```bash
# Download the complete chart
helm pull flyteorg/flyte-binary --untar

# Now you have locally:
flyte-binary/
├── Chart.yaml          # Chart metadata
├── values.yaml         # Default values
├── templates/          # All Kubernetes YAML templates
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── ingress.yaml
│   └── ...
└── charts/             # Dependencies
```

**Your Understanding**: ✅ Correct - You can and should download templates locally for enterprise use

### Step 5: Understanding Images 🐳

**Your Question**: "Where are the Docker images specified?"

Images are defined in multiple places:

```bash
# 1. In values.yaml (default images)
helm show values flyteorg/flyte-binary | grep -A 10 image:

# 2. In templates (using values)
# templates/deployment.yaml will have:
# image: {{ .Values.flyteadmin.image.repository }}:{{ .Values.flyteadmin.image.tag }}

# 3. You can override in your custom values
# your-values.yaml:
flyteadmin:
  image:
    repository: your-registry.com/flyteadmin
    tag: v1.10.7
```

### Step 6: No Helm Login Required ❌

**Your Understanding**: ❌ Incorrect - Helm doesn't require login for public repositories

You only need authentication for:
- Private Helm repositories
- Private Docker registries (handled by Kubernetes)

### Step 7: Installation Process 🚀

```bash
# Option A: Install directly from repository
helm install my-flyte flyteorg/flyte-binary -f my-values.yaml

# Option B: Install from local chart
helm install my-flyte ./flyte-binary/ -f my-values.yaml

# What happens internally:
# 1. Helm reads templates from chart
# 2. Merges your values with defaults
# 3. Renders final Kubernetes YAML
# 4. Applies YAML to cluster using kubectl
```

**Your Understanding**: ✅ Mostly correct - Helm can create namespaces and any Kubernetes resource

### Step 8: Upgrades and Management 🔄

```bash
# Upgrade (change values or chart version)
helm upgrade my-flyte flyteorg/flyte-binary -f my-values.yaml

# Rollback to previous version
helm rollback my-flyte 1

# Uninstall (not "destroy")
helm uninstall my-flyte
```

## Understanding Your Current Setup

Looking at your `flyte-values.yaml`, here's what it does:

### Configuration Structure
```yaml
configuration:
  database:
    # These variables get substituted with real values
    username: "${DB_USERNAME}"          # From environment
    host: "${DB_HOST}"                 # Your RDS endpoint
    # ... other database settings

  storage:
    metadataContainer: "${METADATA_BUCKET}"  # Your S3 bucket
    provider: s3                            # Use AWS S3
```

### Service Account (IRSA)
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "${FLYTE_BACKEND_ROLE_ARN}"
```
This tells EKS to assume an IAM role for AWS access.

### Volume Mounts
```yaml
extraVolumeMounts:
  - name: db-secret
    mountPath: /etc/db-secret
```
This mounts your database password from Kubernetes secrets.

## Helm Architecture Deep Dive

### What Happens During `helm install`

1. **Template Rendering**:
   ```bash
   # You can see what Helm will create before installing
   helm template my-flyte flyteorg/flyte-binary -f my-values.yaml > rendered.yaml
   ```

2. **Resource Creation**:
   - Helm applies YAML to Kubernetes
   - Creates Deployment, Service, ConfigMap, Secret, etc.
   - Tracks the release in cluster metadata

3. **Release Management**:
   ```bash
   # Helm stores release info in Kubernetes
   kubectl get secrets -l owner=helm
   ```

### Helm vs kubectl

| Helm | kubectl |
|------|---------|
| `helm install app chart/` | `kubectl apply -f deployment.yaml -f service.yaml -f ...` |
| `helm upgrade app chart/` | Update each YAML file and `kubectl apply` |
| `helm rollback app 1` | Manually revert each resource |
| `helm uninstall app` | `kubectl delete` each resource individually |

## Enterprise Setup: Local Artifacts Only

For your company requirements (no internet access, local artifacts), here's the complete setup:

### 1. Download and Store Charts Locally

```bash
# Create a local chart repository structure
mkdir -p charts/flyte-binary
cd charts/

# Download the chart
helm pull flyteorg/flyte-binary --untar
helm pull flyteorg/flyte-binary --destination . # Gets .tgz file too

# Your directory structure:
charts/
├── flyte-binary/           # Extracted chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
└── flyte-binary-1.10.7.tgz # Packaged chart
```

### 2. Identify and Download All Images

```bash
# Extract all image references
helm template charts/flyte-binary/ | grep -E "image:|repository:" | sort | uniq

# Common Flyte images you'll need:
# - cr.flyte.org/flyteorg/flyteadmin:v1.10.7
# - cr.flyte.org/flyteorg/flytepropeller:v1.10.7
# - cr.flyte.org/flyteorg/datacatalog:v1.10.7
# - postgres:13-alpine (if using bundled DB)
# - redis:6-alpine (if using bundled Redis)
```

### 3. Set Up Private Registry

```bash
# Tag and push to your private registry
docker pull cr.flyte.org/flyteorg/flyteadmin:v1.10.7
docker tag cr.flyte.org/flyteorg/flyteadmin:v1.10.7 your-registry.com/flyteadmin:v1.10.7
docker push your-registry.com/flyteadmin:v1.10.7

# Repeat for all images
```

### 4. Create Custom Values for Private Registry

```yaml
# private-registry-values.yaml
flyteadmin:
  image:
    repository: your-registry.com/flyteadmin
    tag: v1.10.7

flytepropeller:
  image:
    repository: your-registry.com/flytepropeller
    tag: v1.10.7

datacatalog:
  image:
    repository: your-registry.com/datacatalog
    tag: v1.10.7

# Add all other image overrides
```

## Complete Enterprise Deployment Guide

### Step 1: Prepare Local Environment

```bash
# 1. Create project structure
mkdir -p enterprise-flyte/{charts,config,scripts}
cd enterprise-flyte/

# 2. Download Flyte chart
helm repo add flyteorg https://flyteorg.github.io/flyte  # One-time on internet-connected machine
helm pull flyteorg/flyte-binary --untar --destination charts/

# 3. Create local Helm repository
helm repo index charts/ --url file://$(pwd)/charts

# 4. Package everything for offline transfer
tar -czf flyte-enterprise-package.tgz charts/ config/ scripts/
```

### Step 2: Set Up Private Registry

```bash
# Script to download and retag all images
#!/bin/bash
# download-images.sh

REGISTRY="your-private-registry.com"
IMAGES=(
  "cr.flyte.org/flyteorg/flyteadmin:v1.10.7"
  "cr.flyte.org/flyteorg/flytepropeller:v1.10.7"
  "cr.flyte.org/flyteorg/datacatalog:v1.10.7"
  "postgres:13-alpine"
  "redis:6-alpine"
)

for image in "${IMAGES[@]}"; do
  echo "Processing $image"
  docker pull "$image"
  
  # Extract image name and tag
  name=$(echo "$image" | cut -d'/' -f3)
  
  # Tag for private registry
  docker tag "$image" "$REGISTRY/$name"
  
  # Push to private registry
  docker push "$REGISTRY/$name"
done
```

### Step 3: Create Enterprise Values File

```yaml
# config/enterprise-values.yaml
global:
  # Use private registry for all images
  imageRegistry: your-private-registry.com

flyteadmin:
  image:
    repository: your-private-registry.com/flyteadmin
    tag: v1.10.7

flytepropeller:
  image:
    repository: your-private-registry.com/flytepropeller
    tag: v1.10.7

datacatalog:
  image:
    repository: your-private-registry.com/datacatalog
    tag: v1.10.7

# Database configuration
configuration:
  database:
    username: "${DB_USERNAME}"
    passwordPath: "/etc/db-secret/password"
    host: "${DB_HOST}"
    port: ${DB_PORT}
    dbname: "${DB_NAME}"
    options: "sslmode=require"

# Storage configuration
  storage:
    metadataContainer: "${METADATA_BUCKET}"
    userDataContainer: "${USERDATA_BUCKET}"
    provider: s3

# Pull secrets for private registry
imagePullSecrets:
  - name: private-registry-secret
```

### Step 4: Create Registry Secret

```bash
# Create secret for private registry authentication
kubectl create secret docker-registry private-registry-secret \
  --docker-server=your-private-registry.com \
  --docker-username=your-username \
  --docker-password=your-password \
  --docker-email=your-email@company.com \
  --namespace=flyte
```

### Step 5: Deploy Using Local Chart

```bash
# Install from local chart
helm install flyte-enterprise ./charts/flyte-binary/ \
  --namespace flyte \
  --create-namespace \
  --values config/enterprise-values.yaml \
  --values config/environment-values.yaml
```

### Step 6: Enterprise Deployment Script

```bash
#!/bin/bash
# deploy-enterprise-flyte.sh

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_PATH="$PROJECT_ROOT/charts/flyte-binary"
VALUES_FILE="$PROJECT_ROOT/config/enterprise-values.yaml"
ENV_VALUES="$PROJECT_ROOT/config/environment-values.yaml"
NAMESPACE="flyte"

echo "🚀 Starting Enterprise Flyte Deployment"

# Verify local chart exists
if [[ ! -d "$CHART_PATH" ]]; then
  echo "❌ Chart not found at $CHART_PATH"
  echo "Please run: helm pull flyteorg/flyte-binary --untar --destination charts/"
  exit 1
fi

# Verify values files exist
for file in "$VALUES_FILE" "$ENV_VALUES"; do
  if [[ ! -f "$file" ]]; then
    echo "❌ Values file not found: $file"
    exit 1
  fi
done

# Create namespace if it doesn't exist
echo "📦 Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create registry secret
echo "🔐 Creating private registry secret"
kubectl create secret docker-registry private-registry-secret \
  --docker-server="${PRIVATE_REGISTRY}" \
  --docker-username="${REGISTRY_USERNAME}" \
  --docker-password="${REGISTRY_PASSWORD}" \
  --docker-email="${REGISTRY_EMAIL}" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

# Deploy Flyte
echo "🎯 Deploying Flyte from local chart"
helm upgrade --install flyte-enterprise "$CHART_PATH" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  --values "$ENV_VALUES" \
  --timeout 10m \
  --wait

echo "✅ Enterprise Flyte deployment completed"
echo "📋 Check status with: kubectl get pods -n $NAMESPACE"
```

## Troubleshooting and Best Practices

### Common Issues and Solutions

#### 1. Image Pull Errors
```bash
# Check if secret is correctly configured
kubectl get secret private-registry-secret -n flyte -o yaml

# Test image pull manually
kubectl run test-pod --image=your-registry.com/flyteadmin:v1.10.7 -n flyte
```

#### 2. Values Not Applied
```bash
# Debug what Helm will actually deploy
helm template flyte-enterprise ./charts/flyte-binary/ \
  --values config/enterprise-values.yaml > debug-output.yaml

# Check specific values
helm get values flyte-enterprise -n flyte
```

#### 3. Chart Dependencies
```bash
# If chart has dependencies, update them
cd charts/flyte-binary/
helm dependency update
```

### Best Practices for Enterprise

1. **Version Pinning**:
   ```yaml
   # Always pin image tags in production
   flyteadmin:
     image:
       tag: "v1.10.7"  # Never use "latest"
   ```

2. **Resource Limits**:
   ```yaml
   resources:
     limits:
       cpu: "2000m"
       memory: "4Gi"
     requests:
       cpu: "500m"
       memory: "1Gi"
   ```

3. **Security**:
   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 1000
     readOnlyRootFilesystem: true
   ```

4. **Monitoring**:
   ```yaml
   serviceMonitor:
     enabled: true
   ```

### Git Repository Structure

For your Git repository, organize like this:

```
enterprise-flyte/
├── charts/
│   └── flyte-binary/           # Local chart copy
├── config/
│   ├── enterprise-values.yaml # Private registry config
│   ├── environment.env         # Environment variables
│   └── secrets/               # Secret templates
├── scripts/
│   ├── deploy-enterprise.sh   # Deployment script
│   ├── download-images.sh     # Image download script
│   └── validate-deployment.sh # Validation script
├── docs/
│   └── DEPLOYMENT_GUIDE.md    # Enterprise-specific docs
└── README.md
```

### Final Verification

After deployment, verify everything works:

```bash
# Check all pods are running
kubectl get pods -n flyte

# Check services
kubectl get svc -n flyte

# Test Flyte API
kubectl port-forward svc/flyte-binary-http -n flyte 8088:8088
curl http://localhost:8088/healthcheck

# Check Flyte Console
kubectl port-forward svc/flyte-binary-http -n flyte 8080:8080
# Open http://localhost:8080/console
```

This comprehensive guide should give you everything you need to understand Helm deeply and deploy Flyte in an enterprise environment with complete local control over all artifacts.
