#!/bin/bash

# Wrapper script for check-status.sh
# This script forwards to the core directory script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_SCRIPT="$SCRIPT_DIR/core/check-status.sh"

if [[ ! -f "$CORE_SCRIPT" ]]; then
    echo "Error: Core script not found at $CORE_SCRIPT"
    exit 1
fi

# Forward all arguments to the core script
exec "$CORE_SCRIPT" "$@"
