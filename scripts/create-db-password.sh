#!/bin/bash

# Simple script to generate a random PostgreSQL password, set it in environment.env, and store in AWS Secrets Manager

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Set up paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/config/environment.env"

# Check if environment file exists
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}[ERROR]${NC} Environment file not found at $ENV_FILE"
    exit 1
fi

# Set AWS profile
export AWS_PROFILE=adfs

# Verify AWS connection
echo "Verifying AWS connection..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Cannot connect to AWS. Please ensure your ADFS credentials are valid."
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Connected to AWS Account: $ACCOUNT_ID"

# Generate a secure random password
echo "Generating secure random password..."
DB_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
echo "Password generated!"

# We don't store the actual password in the environment file anymore,
# only reference the secret name in Secrets Manager
echo "Updating environment file to reference Secrets Manager..."
sed -i.bak 's/DB_PASSWORD_SECRET="[^"]*"/DB_PASSWORD_SECRET="flyte-db-password"/' "$ENV_FILE"
sed -i.bak 's/DB_PASSWORD="[^"]*"/DB_PASSWORD=""/' "$ENV_FILE"

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}[SUCCESS]${NC} Environment file updated to use Secrets Manager"
else
    echo -e "${RED}[ERROR]${NC} Failed to update environment file"
    exit 1
fi

# Store the password in AWS Secrets Manager
echo "Storing password in AWS Secrets Manager..."
aws secretsmanager create-secret \
    --name "flyte-db-password" \
    --description "Flyte database password for account $ACCOUNT_ID" \
    --secret-string "$DB_PASSWORD" 2>/dev/null || \
aws secretsmanager update-secret \
    --secret-id "flyte-db-password" \
    --secret-string "$DB_PASSWORD"

if [[ $? -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Failed to store password in AWS Secrets Manager"
    exit 1
fi
echo -e "${GREEN}[SUCCESS]${NC} Password stored in AWS Secrets Manager"

# Update RDS database password
echo "Updating PostgreSQL RDS instance with new password..."
DB_INSTANCE_ID="education-eks-vv8vcaqw-flyte-db"
aws rds modify-db-instance \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --master-user-password "$DB_PASSWORD" \
    --apply-immediately

if [[ $? -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Failed to update RDS instance password"
    echo "The password is still set in the environment file and AWS Secrets Manager,"
    echo "but you'll need to update the database password manually through the AWS Console."
    exit 1
fi
echo -e "${GREEN}[SUCCESS]${NC} RDS database password updated"
echo "Note: It may take a few minutes for the password change to take effect"

echo ""
echo "Database password has been:"
echo "1. Generated securely (16 random alphanumeric characters)"
echo "2. Set in $ENV_FILE"
echo "3. Stored in AWS Secrets Manager as 'flyte-db-password'"
echo "4. Applied to the RDS database instance"
echo ""

# Offer to test the connection
echo "Would you like to test the database connection? (y/n)"
read -p "(Note: It may take a few minutes for the password change to take effect): " test_connection

if [[ "$test_connection" =~ ^[Yy]$ ]]; then
    echo "Testing database connection..."
    echo "Note: If this fails, wait a few minutes and try again as AWS RDS password changes take time to propagate."
    
    if command -v psql &> /dev/null; then
        export PGPASSWORD="$DB_PASSWORD"
        if psql -h "education-eks-vv8vcaqw-flyte-db.cdhzgmmntzio.us-east-1.rds.amazonaws.com" \
               -U postgres \
               -d flyteadmin \
               -c "SELECT version();" 2>/dev/null; then
            echo -e "${GREEN}[SUCCESS]${NC} Database connection successful!"
        else
            echo -e "${RED}[WARNING]${NC} Database connection failed"
            echo "Possible reasons:"
            echo "  - Password change is still being applied (wait a few minutes)"
            echo "  - Security groups don't allow connections from your IP"
            echo "  - Network connectivity issues"
            echo ""
            echo "Try testing from inside the EKS cluster using:"
            echo "  kubectl run postgres-client --image=postgres:14 --rm -it --command -- psql -h education-eks-vv8vcaqw-flyte-db.cdhzgmmntzio.us-east-1.rds.amazonaws.com -U postgres -d flyteadmin"
        fi
        unset PGPASSWORD
    else
        echo -e "${RED}[WARNING]${NC} psql client not found. Cannot test connection locally."
        echo "You can test the connection later from inside the EKS cluster."
    fi
fi

echo ""
echo "You can now continue with Flyte deployment:"
echo "  ./scripts/deploy.sh"
echo ""
