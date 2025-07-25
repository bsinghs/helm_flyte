#!/bin/bash
set -e

# Flyte Deployment Script for AWS EKS
# This script deploys Flyte using Helm on an existing EKS cluster

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
print_header() {
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${BLUE} $1 ${NC}"
    echo -e "${BLUE}============================================${NC}\n"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

print_header "🚀 Starting Flyte Deployment"

# Check if environment file exists
ENV_FILE="$PROJECT_ROOT/config/environment.env"
if [[ -f "$ENV_FILE" ]]; then
    print_status "Loading environment variables from $ENV_FILE"
    source "$ENV_FILE"
else
    print_warning "Environment file not found at $ENV_FILE"
    print_status "Please ensure the following environment variables are set:"
    echo "  - CLUSTER_NAME"
    echo "  - AWS_REGION"
    echo "  - DB_HOST, DB_PASSWORD"
    echo "  - METADATA_BUCKET, USERDATA_BUCKET"
    echo "  - FLYTE_BACKEND_ROLE_ARN, FLYTE_USER_ROLE_ARN, ALB_CONTROLLER_ROLE_ARN"
fi

# Check prerequisites
print_header "🔍 Checking Prerequisites"

# Required commands
REQUIRED_COMMANDS=("kubectl" "helm" "aws" "envsubst")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        print_error "$cmd is required but not installed"
        exit 1
    else
        print_status "$cmd is installed"
    fi
done

# Check required environment variables
REQUIRED_VARS=("CLUSTER_NAME" "AWS_REGION" "DB_HOST" "METADATA_BUCKET" "USERDATA_BUCKET")
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var}" ]]; then
        print_error "Required environment variable $var is not set"
        exit 1
    else
        print_status "$var is set"
    fi
done

# Set defaults for optional variables
export DB_PORT="${DB_PORT:-5432}"
export DB_NAME="${DB_NAME:-flyteadmin}"
export DB_USERNAME="${DB_USERNAME:-postgres}"
export FLYTE_VERSION="${FLYTE_VERSION:-v1.10.6}"
export FLYTE_NAMESPACE="${FLYTE_NAMESPACE:-flyte}"
export FLYTE_BACKEND_CPU_REQUEST="${FLYTE_BACKEND_CPU_REQUEST:-500m}"
export FLYTE_BACKEND_MEMORY_REQUEST="${FLYTE_BACKEND_MEMORY_REQUEST:-1Gi}"
export FLYTE_BACKEND_CPU_LIMIT="${FLYTE_BACKEND_CPU_LIMIT:-2}"
export FLYTE_BACKEND_MEMORY_LIMIT="${FLYTE_BACKEND_MEMORY_LIMIT:-4Gi}"

print_header "🔐 AWS and Kubernetes Setup"

# Check AWS authentication
print_status "Checking AWS authentication..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS authentication failed. Please configure your AWS CLI."
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_status "Connected to AWS Account: $ACCOUNT_ID"

# Update kubeconfig
print_status "Updating kubeconfig for cluster: $CLUSTER_NAME"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

# Test cluster connectivity
print_status "Testing cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

CURRENT_CONTEXT=$(kubectl config current-context)
print_status "Connected to cluster: $CURRENT_CONTEXT"

print_header "📦 Setting up Helm Repositories"

# Add Helm repositories
print_status "Adding Helm repositories..."
helm repo add flyteorg https://flyteorg.github.io/flyte
helm repo add eks https://aws.github.io/eks-charts
helm repo update

print_header "🔧 Deploying AWS Load Balancer Controller"

# Check if ALB Controller is already installed
if kubectl get deployment -n kube-system aws-load-balancer-controller &> /dev/null; then
    print_status "AWS Load Balancer Controller already installed, skipping..."
else
    print_status "Installing AWS Load Balancer Controller..."
    
    # Create temporary values file with substituted variables
    ALB_VALUES_TEMP=$(mktemp)
    envsubst < "$PROJECT_ROOT/helm/alb-controller-values.yaml" > "$ALB_VALUES_TEMP"
    
    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --values "$ALB_VALUES_TEMP" \
        --wait \
        --timeout 10m
    
    rm "$ALB_VALUES_TEMP"
    print_success "AWS Load Balancer Controller installed successfully"
fi

print_header "🗄️ Setting up Database Secret"

# Create Flyte namespace
print_status "Creating Flyte namespace: $FLYTE_NAMESPACE"
kubectl create namespace "$FLYTE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Handle database password
if [[ -z "$DB_PASSWORD" ]]; then
    print_warning "DB_PASSWORD not set. Attempting to retrieve from AWS Secrets Manager..."
    DB_PASSWORD=$(aws secretsmanager get-secret-value \
        --secret-id "flyte-db-password" \
        --query SecretString --output text 2>/dev/null || echo "")
    
    if [[ -z "$DB_PASSWORD" ]]; then
        print_error "Database password not found. Set DB_PASSWORD environment variable or store in AWS Secrets Manager with key 'flyte-db-password'."
        exit 1
    fi
    print_status "Retrieved database password from AWS Secrets Manager"
fi

# Create database secret
print_status "Creating database secret..."
kubectl create secret generic flyte-db-secret \
    --from-literal=password="$DB_PASSWORD" \
    --namespace="$FLYTE_NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

print_header "🚁 Deploying Flyte"

# Create temporary values file with substituted variables
FLYTE_VALUES_TEMP=$(mktemp)
envsubst < "$PROJECT_ROOT/helm/flyte-values.yaml" > "$FLYTE_VALUES_TEMP"

print_status "Deploying Flyte Binary chart..."
helm upgrade --install flyte-binary flyteorg/flyte-binary \
    --namespace "$FLYTE_NAMESPACE" \
    --values "$FLYTE_VALUES_TEMP" \
    --version "$FLYTE_VERSION" \
    --wait \
    --timeout 15m

rm "$FLYTE_VALUES_TEMP"

print_header "⏳ Waiting for Flyte to be Ready"

# Wait for pods to be ready
print_status "Waiting for Flyte pods to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=flyte-binary \
    -n "$FLYTE_NAMESPACE" \
    --timeout=300s

print_header "✅ Deployment Verification"

# Get deployment status
print_status "Checking deployment status..."
kubectl get pods -n "$FLYTE_NAMESPACE"
echo ""
kubectl get services -n "$FLYTE_NAMESPACE"
echo ""

# Check for ingress
if kubectl get ingress -n "$FLYTE_NAMESPACE" &> /dev/null; then
    echo "Ingress configuration:"
    kubectl get ingress -n "$FLYTE_NAMESPACE"
    echo ""
fi

print_success "🎉 Flyte deployment completed successfully!"

print_header "🎯 Next Steps"

echo "1. Check status:"
echo "   kubectl get pods -n $FLYTE_NAMESPACE"
echo ""
echo "2. Access Flyte Console:"
echo "   # Option 1: Port forward (for development)"
echo "   ./scripts/port-forward.sh"
echo "   # Then visit: http://localhost:8080/console"
echo ""
echo "   # Option 2: Use ingress URL (if configured)"
echo "   kubectl get ingress -n $FLYTE_NAMESPACE"
echo ""
echo "3. Install flytectl CLI:"
echo "   curl -sL https://ctl.flyte.org/install | bash"
echo ""
echo "4. Configure flytectl:"
echo "   flytectl config init --host localhost:8080  # or your ingress URL"
echo ""
echo "5. Test Flyte:"
echo "   flytectl version"
echo "   flytectl get projects"
echo ""
echo "6. Check deployment details:"
echo "   ./scripts/check-status.sh"

print_success "Deployment completed! 🚀"
