#!/bin/bash

# Cleanup Script for Flyte Deployment
# This script removes all Flyte components from the cluster

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

FLYTE_NAMESPACE="${FLYTE_NAMESPACE:-flyte}"

print_header "🧹 Flyte Cleanup"

# Confirmation prompt
read -p "Are you sure you want to remove Flyte deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

print_status "Starting cleanup process..."

# Remove Flyte Helm release
print_status "Removing Flyte Helm release..."
helm uninstall flyte-binary -n "$FLYTE_NAMESPACE" || print_warning "Flyte release not found or already removed"

# Remove AWS Load Balancer Controller (optional)
read -p "Remove AWS Load Balancer Controller? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Removing AWS Load Balancer Controller..."
    helm uninstall aws-load-balancer-controller -n kube-system || print_warning "ALB Controller not found or already removed"
fi

# Remove namespace
print_status "Removing Flyte namespace..."
kubectl delete namespace "$FLYTE_NAMESPACE" || print_warning "Namespace not found or already removed"

# Remove secrets from AWS Secrets Manager (optional)
read -p "Remove database password from AWS Secrets Manager? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Removing secret from AWS Secrets Manager..."
    aws secretsmanager delete-secret --secret-id "flyte-db-password" --force-delete-without-recovery || print_warning "Secret not found or already removed"
fi

print_status "✅ Cleanup completed"

echo ""
echo "Remaining items (if any):"
echo "- Infrastructure resources (EKS, RDS, S3) - managed separately"
echo "- Helm repositories - kept for future use"
echo "- kubectl configuration - unchanged"
