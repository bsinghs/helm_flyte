#!/bin/bash

# Sample script showing how to use the database password from AWS Secrets Manager
# in deployment and connection scenarios

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/config/environment.env"

# Source the environment file to get variables
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    print_error "Environment file not found at $ENV_FILE"
    exit 1
fi

# Source the password retrieval script
source "$SCRIPT_DIR/get-db-password.sh"

# Example: Get database password
print_header "Getting Database Password from AWS Secrets Manager"
DB_PASSWORD=$(get_db_password "${DB_PASSWORD_SECRET:-flyte-db-password}")

if [[ $? -ne 0 ]]; then
    print_error "Failed to get database password from AWS Secrets Manager"
    exit 1
fi

print_status "Successfully retrieved database password from AWS Secrets Manager"

# Example: Test database connection
print_header "Testing Database Connection"
print_status "Connecting to PostgreSQL database using password from Secrets Manager..."

if command -v psql &> /dev/null; then
    # Set PGPASSWORD environment variable for psql connection
    export PGPASSWORD="$DB_PASSWORD"
    
    if psql -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT version();" &>/dev/null; then
        print_status "✅ Database connection successful!"
    else
        print_error "❌ Database connection failed"
        echo "Possible reasons:"
        echo "  - Password is incorrect or has changed"
        echo "  - Security groups don't allow connections from your IP"
        echo "  - Network connectivity issues"
    fi
    unset PGPASSWORD
else
    print_error "psql client not found. Cannot test connection locally."
fi

# Example: Use in Kubernetes
print_header "Using Secret in Kubernetes Deployment"
print_status "Here's how you would use this in a Kubernetes deployment:"

cat << EOF

# Create a Kubernetes Secret with the database password
kubectl create secret generic flyte-db-credentials \\
    --from-literal=password='$DB_PASSWORD' \\
    --namespace=$FLYTE_NAMESPACE

# In your deployment YAML, reference it like this:
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flyte-db-client
spec:
  template:
    spec:
      containers:
      - name: app
        image: flyteorg/flyteadmin:$FLYTE_VERSION
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: flyte-db-credentials
              key: password
EOF

print_header "Security Best Practices"
echo "1. The actual password is never stored in the environment file"
echo "2. The password is retrieved from AWS Secrets Manager only when needed"
echo "3. For Kubernetes deployments, create a K8s Secret from the AWS Secret"
echo "4. The password is never printed to logs or terminal output"
echo "5. Environment variables are unset after use"
echo ""

print_status "This approach separates configuration from secrets management"
echo "Your workflow is now more secure and follows cloud-native best practices!"
