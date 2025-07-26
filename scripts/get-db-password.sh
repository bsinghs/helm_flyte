#!/bin/bash

# Script to retrieve the PostgreSQL database password from AWS Secrets Manager
# This script can be sourced by other scripts to get the password securely

# Set up colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

get_db_password() {
    local secret_name="$1"
    
    if [[ -z "$secret_name" ]]; then
        echo -e "${RED}[ERROR]${NC} Secret name not provided"
        return 1
    fi
    
    # Set AWS profile
    export AWS_PROFILE=adfs
    
    # Retrieve the password from AWS Secrets Manager
    local password
    password=$(aws secretsmanager get-secret-value \
        --secret-id "$secret_name" \
        --query SecretString \
        --output text 2>/dev/null)
        
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Failed to retrieve password from AWS Secrets Manager"
        return 1
    fi
    
    echo "$password"
    return 0
}

# If this script is being sourced, only define the function
# If this script is being executed directly, run the function with arguments
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced
    :  # No operation needed, function is defined
else
    # Script is being executed directly
    if [[ $# -eq 0 ]]; then
        # Load environment file to get secret name
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
        ENV_FILE="$PROJECT_ROOT/config/environment.env"
        
        if [[ -f "$ENV_FILE" ]]; then
            # Source the environment file to get variables
            source "$ENV_FILE"
            secret_name="${DB_PASSWORD_SECRET:-flyte-db-password}"
        else
            secret_name="flyte-db-password"  # Default fallback
        fi
    else
        secret_name="$1"
    fi
    
    password=$(get_db_password "$secret_name")
    if [[ $? -eq 0 ]]; then
        echo "$password"
        exit 0
    else
        exit 1
    fi
fi
