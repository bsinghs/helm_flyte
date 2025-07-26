#!/bin/bash
# Flyte Teardown Script
# This script tears down a Flyte deployment and associated AWS resources

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

# Get absolute path of script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
ENV_FILE="$PROJECT_ROOT/config/environment.env"
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    print_status "Environment loaded from $ENV_FILE"
else
    print_error "Environment file not found at $ENV_FILE. Cannot proceed with teardown."
    exit 1
fi

print_header "🧹 Starting Flyte Teardown"

# Set AWS profile if not already set
export AWS_PROFILE=${AWS_PROFILE:-adfs}
print_status "Using AWS profile: $AWS_PROFILE"

# Check AWS authentication
print_status "Verifying AWS authentication..."
if ! aws sts get-caller-identity > /dev/null; then
    print_error "AWS authentication failed. Please check your credentials."
    exit 1
fi
print_status "AWS authentication successful"

# Function to confirm actions
confirm_action() {
    echo -e "${YELLOW}WARNING: This action will delete $1. Are you sure? (y/n)${NC}"
    read -r response
    if [[ "$response" != "y" ]]; then
        echo "Skipping $1 deletion."
        return 1
    fi
    return 0
}

print_header "🗑️ Removing Kubernetes Resources"

# Delete Flyte Helm release
if kubectl get ns flyte &>/dev/null; then
    if confirm_action "Flyte Helm release and namespace"; then
        print_status "Uninstalling Flyte Helm release..."
        helm uninstall flyte-binary -n flyte || print_warning "Failed to uninstall Helm release, continuing anyway"
        
        print_status "Deleting Flyte namespace..."
        kubectl delete namespace flyte --wait=false || print_warning "Failed to delete namespace, continuing anyway"
        print_status "Kubernetes resources deletion initiated (may take some time to complete)"
    fi
else
    print_status "Flyte namespace not found, skipping Kubernetes resource deletion"
fi

print_header "🗑️ Removing AWS Resources"

# Delete AWS Secrets Manager secret
if [[ -n "${DB_PASSWORD_SECRET}" ]]; then
    if confirm_action "AWS Secrets Manager secret '${DB_PASSWORD_SECRET}' PERMANENTLY (no recovery window)"; then
        print_status "Permanently deleting AWS Secrets Manager secret (no recovery window)..."
        if aws secretsmanager delete-secret --secret-id "${DB_PASSWORD_SECRET}" --force-delete-without-recovery; then
            print_status "Secret deleted successfully (immediate deletion, no recovery possible)"
        else
            print_warning "Failed to delete secret or secret not found"
        fi
    fi
else
    print_warning "DB_PASSWORD_SECRET is not set, skipping Secrets Manager deletion"
fi

# Delete S3 buckets if requested
if [[ -n "${METADATA_BUCKET}" && -n "${USERDATA_BUCKET}" ]]; then
    if confirm_action "S3 buckets (${METADATA_BUCKET} and ${USERDATA_BUCKET}) and ALL their contents"; then
        print_status "Emptying and deleting S3 buckets..."
        
        # Check if metadata bucket exists
        if aws s3 ls "s3://${METADATA_BUCKET}" &>/dev/null; then
            print_status "Emptying metadata bucket..."
            aws s3 rm "s3://${METADATA_BUCKET}" --recursive
            print_status "Deleting metadata bucket..."
            aws s3api delete-bucket --bucket "${METADATA_BUCKET}" || print_warning "Failed to delete metadata bucket"
        else
            print_status "Metadata bucket not found, skipping"
        fi
        
        # Check if userdata bucket exists
        if aws s3 ls "s3://${USERDATA_BUCKET}" &>/dev/null; then
            print_status "Emptying userdata bucket..."
            aws s3 rm "s3://${USERDATA_BUCKET}" --recursive
            print_status "Deleting userdata bucket..."
            aws s3api delete-bucket --bucket "${USERDATA_BUCKET}" || print_warning "Failed to delete userdata bucket"
        else
            print_status "Userdata bucket not found, skipping"
        fi
    fi
else
    print_warning "METADATA_BUCKET or USERDATA_BUCKET is not set, skipping S3 bucket deletion"
fi

# Option to delete IAM roles
if [[ -n "${FLYTE_BACKEND_ROLE_ARN}" || -n "${FLYTE_USER_ROLE_ARN}" ]]; then
    if confirm_action "IAM roles used by Flyte"; then
        # Extract role names from ARNs
        if [[ -n "${FLYTE_BACKEND_ROLE_ARN}" ]]; then
            BACKEND_ROLE_NAME=$(echo "${FLYTE_BACKEND_ROLE_ARN}" | awk -F'/' '{print $NF}')
            print_status "Deleting backend IAM role ${BACKEND_ROLE_NAME}..."
            aws iam delete-role --role-name "${BACKEND_ROLE_NAME}" || print_warning "Failed to delete backend role, it might have attached policies"
        fi
        
        if [[ -n "${FLYTE_USER_ROLE_ARN}" ]]; then
            USER_ROLE_NAME=$(echo "${FLYTE_USER_ROLE_ARN}" | awk -F'/' '{print $NF}')
            print_status "Deleting user IAM role ${USER_ROLE_NAME}..."
            aws iam delete-role --role-name "${USER_ROLE_NAME}" || print_warning "Failed to delete user role, it might have attached policies"
        fi
    fi
fi

print_header "✅ Teardown Process Completed"

print_status "Teardown process has completed. Some resources might still be in the process of being deleted."
print_status "Please verify in the AWS console that all resources have been properly removed."
print_status "Note: Namespace deletion might take some time to complete in the background."
