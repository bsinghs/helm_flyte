#!/bin/bash
# Flyte Deployment Script for AWS EKS
# This script deploys Flyte on an existing EKS cluster using Helm

set -e

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

# Check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is required but not installed"
        return 1
    else
        print_status "$1 is installed"
        return 0
    fi
}

# Get absolute path of script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
ENV_FILE="$PROJECT_ROOT/config/environment.env"
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    print_status "Environment loaded from $ENV_FILE"
else
    print_warning "Environment file not found at $ENV_FILE"
    print_warning "Please ensure the following environment variables are set:"
    print_warning "  - CLUSTER_NAME"
    print_warning "  - AWS_REGION"
    print_warning "  - DB_HOST, DB_PASSWORD_SECRET"
    print_warning "  - METADATA_BUCKET, USERDATA_BUCKET"
    print_warning "  - FLYTE_BACKEND_ROLE_ARN, FLYTE_USER_ROLE_ARN"
fi

print_header "🔍 Checking Prerequisites"

# Check required commands
REQUIRED_COMMANDS=("kubectl" "helm" "aws" "envsubst")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    check_command "$cmd" || exit 1
done

print_header "🛠️ Setting Up Environment"

# Set AWS profile if not already set
export AWS_PROFILE=${AWS_PROFILE:-adfs}
print_status "Using AWS profile: $AWS_PROFILE"

# Check AWS authentication
print_status "Verifying AWS authentication..."
aws sts get-caller-identity > /dev/null || {
    print_error "AWS authentication failed. Please check your credentials."
    exit 1
}
print_status "AWS authentication successful"

# Verify EKS cluster access
print_status "Verifying access to EKS cluster $CLUSTER_NAME..."
kubectl config use-context "arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME}" || {
    print_error "Failed to switch to EKS cluster context. Ensure the cluster exists and you have access."
    exit 1
}
print_status "EKS cluster access verified"

print_header "🚀 Deploying Flyte"

# Add Flyte Helm repository
print_status "Adding Flyte Helm repository..."
helm repo add flyteorg https://flyteorg.github.io/flyte > /dev/null 2>&1 || helm repo update
print_status "Helm repository added"

# Create namespace
print_status "Creating Flyte namespace: ${FLYTE_NAMESPACE:-flyte}..."
kubectl create namespace ${FLYTE_NAMESPACE:-flyte} --dry-run=client -o yaml | kubectl apply -f -
print_status "Namespace created/updated"

# Get DB password from Secrets Manager
print_status "Retrieving database password from AWS Secrets Manager..."
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${DB_PASSWORD_SECRET} --query 'SecretString' --output text)
if [[ -z "$DB_PASSWORD" ]]; then
    print_error "Failed to retrieve database password from AWS Secrets Manager"
    exit 1
fi
print_status "Database password retrieved"

# Create Kubernetes secret for database password
print_status "Creating Kubernetes secret for database password..."
kubectl create secret generic flyte-db-pass \
  --namespace ${FLYTE_NAMESPACE:-flyte} \
  --from-literal=postgres-password=${DB_PASSWORD} \
  --dry-run=client -o yaml | kubectl apply -f -
print_status "Kubernetes secret created"

# Create temporary values file
VALUES_FILE=$(mktemp)
print_status "Creating Helm values file at $VALUES_FILE..."

cat > $VALUES_FILE << EOL
# Configuration section
configuration:
  database:
    username: "${DB_USERNAME}"
    password: "${DB_PASSWORD}"  # Direct password instead of path
    host: "${DB_HOST}"
    port: ${DB_PORT}
    dbname: "${DB_NAME}"
    options: "sslmode=require"
    
  storage:
    metadataContainer: "${METADATA_BUCKET}"
    userDataContainer: "${USERDATA_BUCKET}"
    provider: s3
    providerConfig:
      s3:
        region: "${AWS_REGION}"
        authType: "iam"
        disableSSL: false
        v2Signing: false

# Init container modification for database connection
initContainers:
  - name: wait-for-db
    image: postgres:15-alpine
    command:
      - sh
      - -ec
      - |
        until pg_isready -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USERNAME}
        do
          echo waiting for database
          sleep 2
        done

# Service account with IRSA for Flyte backend
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: "${FLYTE_BACKEND_ROLE_ARN}"
EOL

print_status "Helm values file created"

# Install Flyte using Helm
print_status "Installing Flyte ${FLYTE_VERSION:-v1.10.6} to namespace ${FLYTE_NAMESPACE:-flyte}..."
helm upgrade --install flyte-binary flyteorg/flyte-binary \
  --version ${FLYTE_VERSION:-v1.10.6} \
  --namespace ${FLYTE_NAMESPACE:-flyte} \
  --values $VALUES_FILE

# Clean up temporary values file
rm $VALUES_FILE
print_status "Temporary values file removed"

print_header "🔍 Verifying Deployment"

# Wait for pods to be ready
print_status "Waiting for Flyte pods to become ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=flyte-binary -n ${FLYTE_NAMESPACE:-flyte} --timeout=300s || {
    print_warning "Timed out waiting for Flyte pods to become ready"
    print_warning "Checking pod status..."
    kubectl get pods -n ${FLYTE_NAMESPACE:-flyte}
}

# Check Flyte services
print_status "Checking Flyte services..."
kubectl get services -n ${FLYTE_NAMESPACE:-flyte}

print_header "✅ Deployment Complete"

print_status "Flyte has been successfully deployed to your EKS cluster!"
print_status "To access the Flyte UI, run:"
print_status "  ./scripts/flyte-ui.sh"
print_status ""
print_status "For more information, see the FLYTE_DEPLOYMENT_GUIDE.md file."
