#!/bin/bash

# Port Forward Script for Flyte Console Access
# This script sets up port forwarding to access Flyte Console locally

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FLYTE_NAMESPACE="${FLYTE_NAMESPACE:-flyte}"

echo -e "${BLUE}🌐 Setting up port forwarding to Flyte Console...${NC}"
echo -e "${GREEN}Flyte Console will be available at: http://localhost:8080/console${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop port forwarding${NC}"
echo ""

# Check if the service exists
if ! kubectl get service -n "$FLYTE_NAMESPACE" flyte-binary &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Flyte service not found in namespace '$FLYTE_NAMESPACE'"
    echo "Please ensure Flyte is deployed first by running: ./scripts/deploy.sh"
    exit 1
fi

echo "Starting port forward..."
kubectl port-forward -n "$FLYTE_NAMESPACE" service/flyte-binary 8080:8080
