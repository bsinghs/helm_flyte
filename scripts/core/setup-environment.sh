#!/bin/bash

# Setup Environment Script for Flyte Deployment
# This script helps you complete the environment configuration

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/config/environment.env"

print_header "🔧 Flyte Environment Setup"

# Check if environment file exists
if [[ ! -f "$ENV_FILE" ]]; then
    print_error "Environment file not found at $ENV_FILE"
    exit 1
fi

print_status "Environment file found: $ENV_FILE"

# Set AWS profile
export AWS_PROFILE=adfs

# Verify AWS connection
print_status "Verifying AWS connection..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "Cannot connect to AWS. Please ensure your ADFS credentials are valid."
    echo "You may need to re-authenticate with ADFS."
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_status "Connected to AWS Account: $ACCOUNT_ID"

# Database password setup
print_header "🔐 Database Password Setup"

echo "Your RDS instance is:"
echo "  Host: education-eks-vv8vcaqw-flyte-db.cdhzgmmntzio.us-east-1.rds.amazonaws.com"
echo "  Username: postgres"
echo "  Database: flyteadmin"
echo ""

# Check if password is already in environment file
if grep -q "DB_PASSWORD=\"\"" "$ENV_FILE"; then
    print_warning "Database password is not set in environment file."
    echo ""
    echo "Please choose an option:"
    echo "1. Generate random password automatically (recommended)"
    echo "2. Enter password manually"
    echo "3. Skip for now (you'll need to set it before deployment)"
    echo ""
    read -p "Choose option (1-3): " choice

    case $choice in
        1)
            print_status "Running password creation script..."
            "$SCRIPT_DIR/create-db-password.sh"
            ;;
        2)
            echo ""
            read -s -p "Enter your RDS database password: " db_password
            echo ""
            if [[ -n "$db_password" ]]; then
                # Update environment file
                sed -i.bak "s/DB_PASSWORD=\"\"/DB_PASSWORD=\"$db_password\"/" "$ENV_FILE"
                print_status "Password updated in environment file"
                
                # Ask about storing in Secrets Manager
                read -p "Also store in AWS Secrets Manager? (y/n): " store_secret
                if [[ "$store_secret" =~ ^[Yy]$ ]]; then
                    aws secretsmanager create-secret \
                        --name "flyte-db-password" \
                        --description "Flyte database password for account 245966534215" \
                        --secret-string "$db_password" 2>/dev/null || \
                    aws secretsmanager update-secret \
                        --secret-id "flyte-db-password" \
                        --secret-string "$db_password"
                    print_status "Password stored in AWS Secrets Manager"
                fi
            else
                print_warning "No password entered"
            fi
            ;;
        3)
            print_warning "Skipping password setup. Remember to set DB_PASSWORD before deployment."
            ;;
        *)
            print_warning "Invalid choice. Skipping password setup."
            ;;
    esac
else
    print_status "Database password is already set in environment file"
fi

# Update kubeconfig
print_header "⚙️ Kubernetes Configuration"
print_status "Updating kubeconfig for EKS cluster..."
aws eks update-kubeconfig --region us-east-1 --name education-eks-vV8VCAqw

# Test cluster connectivity
if kubectl cluster-info &> /dev/null; then
    print_status "✅ Successfully connected to EKS cluster"
else
    print_warning "⚠️ Could not connect to EKS cluster. Check your permissions."
fi

print_header "📋 Environment Summary"

echo "Your environment is configured with:"
echo "  AWS Account: 245966534215"
echo "  AWS Profile: adfs"
echo "  EKS Cluster: education-eks-vV8VCAqw"
echo "  RDS Host: education-eks-vv8vcaqw-flyte-db.cdhzgmmntzio.us-east-1.rds.amazonaws.com"
echo "  Metadata Bucket: education-eks-vv8vcaqw-flyte-metadata-vv8vcaqw"
echo "  Userdata Bucket: education-eks-vv8vcaqw-flyte-userdata-vv8vcaqw"
echo ""

print_header "🚀 Next Steps"

echo "1. Verify your environment file:"
echo "   cat $ENV_FILE"
echo ""
echo "2. Manage database password (if needed):"
echo "   ./scripts/create-db-password.sh"
echo ""
echo "3. Deploy Flyte:"
echo "   export AWS_PROFILE=adfs"
echo "   ./scripts/deploy.sh"
echo ""
echo "4. Check deployment status:"
echo "   ./scripts/check-status.sh"
echo ""
echo "5. Access Flyte Console:"
echo "   ./scripts/port-forward.sh"
echo ""

print_status "✅ Environment setup completed!"
