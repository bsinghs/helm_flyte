#!/bin/bash

# Flyte Status Check Script
# This script checks the status of your Flyte deployment

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

FLYTE_NAMESPACE="${FLYTE_NAMESPACE:-flyte}"

print_header "🔍 Flyte Deployment Status Check"

# Check if namespace exists
if ! kubectl get namespace "$FLYTE_NAMESPACE" &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Flyte namespace '$FLYTE_NAMESPACE' not found"
    echo "Please deploy Flyte first by running: ./scripts/deploy.sh"
    exit 1
fi

print_header "📦 Pods Status"
kubectl get pods -n "$FLYTE_NAMESPACE" -o wide

print_header "🔗 Services"
kubectl get services -n "$FLYTE_NAMESPACE"

print_header "🌐 Ingress"
if kubectl get ingress -n "$FLYTE_NAMESPACE" &> /dev/null; then
    kubectl get ingress -n "$FLYTE_NAMESPACE"
else
    echo "No ingress resources found"
fi

print_header "🔐 Secrets"
kubectl get secrets -n "$FLYTE_NAMESPACE"

print_header "📊 Resource Usage"
kubectl top pods -n "$FLYTE_NAMESPACE" 2>/dev/null || echo "Metrics server not available"

print_header "📝 Recent Events"
kubectl get events -n "$FLYTE_NAMESPACE" --sort-by='.lastTimestamp' | tail -10

print_header "🏥 Health Checks"

# Check if pods are ready
READY_PODS=$(kubectl get pods -n "$FLYTE_NAMESPACE" --no-headers | grep "Running" | grep "1/1" | wc -l)
TOTAL_PODS=$(kubectl get pods -n "$FLYTE_NAMESPACE" --no-headers | wc -l)

if [[ "$READY_PODS" -eq "$TOTAL_PODS" && "$TOTAL_PODS" -gt 0 ]]; then
    echo -e "${GREEN}✅ All pods are ready ($READY_PODS/$TOTAL_PODS)${NC}"
else
    echo -e "${YELLOW}⚠️  Some pods are not ready ($READY_PODS/$TOTAL_PODS)${NC}"
fi

# Check service endpoints
SERVICE_ENDPOINTS=$(kubectl get endpoints -n "$FLYTE_NAMESPACE" flyte-binary -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
if [[ -n "$SERVICE_ENDPOINTS" ]]; then
    echo -e "${GREEN}✅ Service endpoints are available${NC}"
else
    echo -e "${YELLOW}⚠️  No service endpoints found${NC}"
fi

print_header "🎯 Access Information"

echo "To access Flyte Console:"
echo "1. Port forward: ./scripts/port-forward.sh"
echo "2. Open browser: http://localhost:8080/console"
echo ""

if kubectl get ingress -n "$FLYTE_NAMESPACE" &> /dev/null; then
    INGRESS_HOST=$(kubectl get ingress -n "$FLYTE_NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [[ -n "$INGRESS_HOST" ]]; then
        echo "3. Ingress URL: https://$INGRESS_HOST/console"
    fi
fi

print_header "🛠️ Troubleshooting Commands"

echo "Check logs:"
echo "  kubectl logs -n $FLYTE_NAMESPACE deployment/flyte-binary"
echo ""
echo "Describe pod:"
echo "  kubectl describe pod -n $FLYTE_NAMESPACE <pod-name>"
echo ""
echo "Check events:"
echo "  kubectl get events -n $FLYTE_NAMESPACE --sort-by='.lastTimestamp'"
