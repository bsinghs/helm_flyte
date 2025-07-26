#!/bin/bash
# Flyte UI Port Forwarding Script
# This script sets up port forwarding to access the Flyte UI

set -e

# Function to check if a port is already in use
check_port_in_use() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

# Default settings
NAMESPACE=${FLYTE_NAMESPACE:-flyte}
LOCAL_PORT=8080
FLYTE_HTTP_SERVICE="flyte-binary-http"
FLYTE_SERVICE_PORT=8088
FLYTE_CONSOLE_URL="http://localhost:${LOCAL_PORT}/console"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -n|--namespace) NAMESPACE="$2"; shift ;;
        -p|--port) LOCAL_PORT="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed. Please install it first."
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "Error: Namespace '$NAMESPACE' does not exist."
    exit 1
fi

# Check if Flyte HTTP service exists
if ! kubectl get service -n "$NAMESPACE" "$FLYTE_HTTP_SERVICE" &> /dev/null; then
    echo "Error: Flyte HTTP service '$FLYTE_HTTP_SERVICE' not found in namespace '$NAMESPACE'."
    echo "Checking available services..."
    kubectl get services -n "$NAMESPACE"
    exit 1
fi

# Check if port is already in use
if check_port_in_use $LOCAL_PORT; then
    echo "Warning: Port $LOCAL_PORT is already in use."
    echo "You may need to stop other processes using this port or use a different port."
    echo "Continue anyway? (y/n)"
    read -r response
    if [[ "$response" != "y" ]]; then
        echo "Aborting."
        exit 1
    fi
fi

echo "Setting up port forwarding for Flyte UI..."
echo "Forwarding local port $LOCAL_PORT to $FLYTE_HTTP_SERVICE:$FLYTE_SERVICE_PORT in namespace $NAMESPACE"
echo
echo "After connection is established, you can access Flyte UI at:"
echo "→ $FLYTE_CONSOLE_URL"
echo
echo "Press Ctrl+C to stop port forwarding."
echo

# Start port forwarding
kubectl port-forward -n "$NAMESPACE" service/"$FLYTE_HTTP_SERVICE" "$LOCAL_PORT":"$FLYTE_SERVICE_PORT"
