# Flyte on AWS EKS: Deployment Guide

This guide documents the process of deploying Flyte on an AWS EKS cluster, including the setup steps, common issues, and their solutions.

## Prerequisites

- AWS CLI configured with appropriate permissions
- `kubectl` installed and configured to connect to your EKS cluster
- `helm` installed (package manager for Kubernetes)
- `gettext` installed (for the `envsubst` command)
- Access to AWS Secrets Manager and appropriate IAM roles

## Deployment Steps

### 1. Prerequisites Setup

```bash
# Install required tools
brew install helm    # Package manager for Kubernetes
brew install gettext # For envsubst command

# Verify AWS CLI and kubectl are installed
command -v kubectl && command -v helm && command -v aws && command -v envsubst

# Set up AWS profile and verify authentication
export AWS_PROFILE=adfs
aws sts get-caller-identity
```

### 2. Environment Configuration

```bash
# Load environment variables from config
source config/environment.env

# Verify environment variables
echo "CLUSTER_NAME=${CLUSTER_NAME}"
echo "AWS_REGION=${AWS_REGION}"
echo "DB_HOST=${DB_HOST}"
echo "METADATA_BUCKET=${METADATA_BUCKET}"
echo "USERDATA_BUCKET=${USERDATA_BUCKET}"
echo "FLYTE_BACKEND_ROLE_ARN=${FLYTE_BACKEND_ROLE_ARN}"
echo "FLYTE_USER_ROLE_ARN=${FLYTE_USER_ROLE_ARN}"
```

### 3. Kubernetes Namespace Creation

```bash
# Create the flyte namespace
kubectl create namespace ${FLYTE_NAMESPACE:-flyte} --dry-run=client -o yaml | kubectl apply -f -
```

### 4. Database Password Management (AWS Secrets Manager → Kubernetes)

```bash
# Retrieve database password from AWS Secrets Manager
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${DB_PASSWORD_SECRET} --query 'SecretString' --output text)

# Create Kubernetes secret with the database password
kubectl create secret generic flyte-db-pass \
  --namespace ${FLYTE_NAMESPACE:-flyte} \
  --from-literal=postgres-password=${DB_PASSWORD} \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 5. Helm Repository Setup

```bash
# Add Flyte Helm repository
helm repo add flyteorg https://flyteorg.github.io/flyte
helm repo update
```

### 6. Helm Values Configuration

```bash
# Create Helm values file with proper configurations
cat > flyte-values-complete.yaml << EOL
# Configuration section
configuration:
  database:
    username: "${DB_USERNAME}"
    password: "${DB_PASSWORD}"  # Direct password instead of path
    host: "${DB_HOST}"
    port: ${DB_PORT}
    dbname: "${DB_NAME}"
    options: "sslmode=require"
    
  storage:
    metadataContainer: "${METADATA_BUCKET}"
    userDataContainer: "${USERDATA_BUCKET}"
    provider: s3
    providerConfig:
      s3:
        region: "${AWS_REGION}"
        authType: "iam"
        disableSSL: false
        v2Signing: false

# Init container modification for database connection
initContainers:
  - name: wait-for-db
    image: postgres:15-alpine
    command:
      - sh
      - -ec
      - |
        until pg_isready -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USERNAME}
        do
          echo waiting for database
          sleep 2
        done

# Service account with IRSA for Flyte backend
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: "${FLYTE_BACKEND_ROLE_ARN}"
EOL
```

### 7. Flyte Deployment with Helm

```bash
# Deploy Flyte using Helm
helm upgrade --install flyte-binary flyteorg/flyte-binary \
  --version ${FLYTE_VERSION:-v1.10.6} \
  --namespace ${FLYTE_NAMESPACE:-flyte} \
  --values flyte-values-complete.yaml
```

### 8. Verify Deployment

```bash
# Check pod status
kubectl get pods -n flyte

# Check logs if needed
kubectl logs -n flyte $(kubectl get pods -n flyte -o jsonpath='{.items[0].metadata.name}')
```

### 9. Access Flyte UI

```bash
# Set up port forwarding to access Flyte UI
kubectl port-forward -n flyte service/flyte-binary-http 8080:8088

# Access the UI at http://localhost:8080/console in your browser
```

## Issues Faced and Solutions

### 1. Script Directory Structure Issue

**Problem:** The deployment script was looking for environment files in the wrong location due to path resolution issues.

**Solution:** We explicitly set the environment path and loaded variables directly:
```bash
PROJECT_ROOT=$(pwd)
ENV_FILE=$PROJECT_ROOT/config/environment.env
source $ENV_FILE
```

### 2. Missing Required Tools

**Problem:** Helm and envsubst tools were not installed.

**Solution:** We installed them using Homebrew:
```bash
brew install helm
brew install gettext
```

### 3. Database Connection Issues

**Problem:** The init container was trying to connect to localhost (127.0.0.1) instead of the RDS instance.

**Solution:** We explicitly configured the init container to connect to the RDS host:
```yaml
initContainers:
  - name: wait-for-db
    image: postgres:15-alpine
    command:
      - sh
      - -ec
      - |
        until pg_isready -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USERNAME}
        do
          echo waiting for database
          sleep 2
        done
```

### 4. Database Password Mount Issues

**Problem:** The database password wasn't correctly mounted in the container, resulting in "missing database password at specified path" errors.

**Solution:** We switched from using a password path to directly setting the password in the configuration:
```yaml
configuration:
  database:
    username: "${DB_USERNAME}"
    password: "${DB_PASSWORD}"  # Direct password instead of path
    # passwordPath: "/etc/db-secret/postgres-password" # Removed
```

### 5. Kubernetes Secret Key Mismatch

**Problem:** The key in the Kubernetes secret didn't match what Flyte was looking for.

**Solution:** We explicitly created the secret with the correct key name:
```bash
kubectl create secret generic flyte-db-pass \
  --namespace ${FLYTE_NAMESPACE:-flyte} \
  --from-literal=postgres-password=${DB_PASSWORD}
```

### 6. Incorrect Port Forwarding

**Problem:** Port forwarding was set up to the wrong service and port (`flyte-binary:80` instead of `flyte-binary-http:8088`).

**Solution:** Used the correct service name and port in the port-forwarding command:
```bash
kubectl port-forward -n flyte service/flyte-binary-http 8080:8088
```

## AWS Secrets Manager to Kubernetes Secrets: Detailed Explanation

### How Database Passwords Flow from AWS to Kubernetes

1. **AWS Secrets Manager Storage**:
   - The database password is initially stored in AWS Secrets Manager with a secret ID (in our case, `flyte-db-password`).
   - This provides centralized, encrypted storage for sensitive credentials.
   - AWS IAM controls who can access these secrets.

2. **Retrieval During Deployment**:
   - Using the AWS CLI, we retrieve the password from Secrets Manager:
     ```bash
     DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${DB_PASSWORD_SECRET} --query 'SecretString' --output text)
     ```
   - This temporarily loads the password into the deployment environment (as an environment variable).

3. **Creation of Kubernetes Secret**:
   - We create a Kubernetes Secret in the flyte namespace:
     ```bash
     kubectl create secret generic flyte-db-pass \
       --namespace ${FLYTE_NAMESPACE:-flyte} \
       --from-literal=postgres-password=${DB_PASSWORD}
     ```
   - This stores the password in Kubernetes' own secret management system.
   - The `--from-literal=postgres-password=${DB_PASSWORD}` part is crucial - it creates a key-value pair in the secret where:
     - `postgres-password` is the key (the name by which the secret value is accessed)
     - `${DB_PASSWORD}` is the value (the actual password)

4. **Configuration in Flyte**:
   - In our final solution, we used the password directly in the Flyte configuration:
     ```yaml
     configuration:
       database:
         password: "${DB_PASSWORD}"
     ```
   - Alternatively, we could have mounted the Kubernetes secret as a volume and accessed it via a file path:
     ```yaml
     configuration:
       database:
         passwordPath: "/etc/db-secret/postgres-password"
     
     extraVolumeMounts:
       - name: db-secret
         mountPath: /etc/db-secret
         readOnly: true
     
     extraVolumes:
       - name: db-secret
         secret:
           secretName: flyte-db-pass
     ```

### Key Differences Between AWS Secrets Manager and Kubernetes Secrets

| Feature | AWS Secrets Manager | Kubernetes Secrets |
|---------|---------------------|-------------------|
| **Scope** | AWS account/region wide | Namespace scoped in a cluster |
| **Security** | Encrypted at rest, IAM-based access control | Base64 encoded by default (not encrypted unless etcd encryption is enabled) |
| **Versioning** | Supports versioning and rotation | No built-in versioning |
| **Access** | AWS SDKs, CLI, API | Mounted as files or environment variables in pods |
| **Auditing** | Full AWS CloudTrail integration | Requires additional auditing setup |
| **Cost** | Pay per secret and API calls | Included with Kubernetes |

### Best Practices for Managing Secrets in This Flow

1. **Limit Access to AWS Secrets Manager**:
   - Use IAM roles with least privilege to access secrets
   - The EKS cluster should use IAM roles that have only the permissions needed

2. **Kubernetes Secret Management**:
   - Create secrets just-in-time during deployment
   - Don't check in manifests with secrets to version control
   - Use `--dry-run=client -o yaml | kubectl apply -f -` pattern to avoid shell history

3. **Pod Security**:
   - Mount secrets as read-only volumes
   - Use Kubernetes RBAC to restrict which pods/users can access which secrets

4. **Automation**:
   - Automate the process to avoid manual handling of secrets
   - Consider tools like External Secrets Operator for production environments to automatically sync AWS Secrets Manager with Kubernetes Secrets

By following this flow, we maintain the security of sensitive credentials while making them available to the applications that need them in a Kubernetes environment.

## Complete Deployment Script

For convenience, here's the complete deployment script that incorporates all of our fixes and learnings:

```bash
#!/bin/bash
set -e

# Change to project directory and load environment
cd /Users/bsingh/Documents/Dev/helm_flyte
source config/environment.env

echo "Setting up Flyte deployment..."

# Set AWS profile
export AWS_PROFILE=${AWS_PROFILE:-adfs}

# Check AWS authentication
aws sts get-caller-identity

# Add Flyte Helm repo
helm repo add flyteorg https://flyteorg.github.io/flyte
helm repo update

# Create namespace if it doesn't exist
kubectl create namespace ${FLYTE_NAMESPACE:-flyte} --dry-run=client -o yaml | kubectl apply -f -

# Get DB password from Secrets Manager
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${DB_PASSWORD_SECRET} --query 'SecretString' --output text)

# Create database secret
kubectl create secret generic flyte-db-pass \
  --namespace ${FLYTE_NAMESPACE:-flyte} \
  --from-literal=postgres-password=${DB_PASSWORD} \
  --dry-run=client -o yaml | kubectl apply -f -

# Create values file
cat > /tmp/flyte-values-complete.yaml << EOL
# Configuration section
configuration:
  database:
    username: "${DB_USERNAME}"
    password: "${DB_PASSWORD}"  # Direct password instead of path
    host: "${DB_HOST}"
    port: ${DB_PORT}
    dbname: "${DB_NAME}"
    options: "sslmode=require"
    
  storage:
    metadataContainer: "${METADATA_BUCKET}"
    userDataContainer: "${USERDATA_BUCKET}"
    provider: s3
    providerConfig:
      s3:
        region: "${AWS_REGION}"
        authType: "iam"
        disableSSL: false
        v2Signing: false

# Init container modification for database connection
initContainers:
  - name: wait-for-db
    image: postgres:15-alpine
    command:
      - sh
      - -ec
      - |
        until pg_isready -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USERNAME}
        do
          echo waiting for database
          sleep 2
        done

# Service account with IRSA for Flyte backend
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: "${FLYTE_BACKEND_ROLE_ARN}"
EOL

echo "Installing Flyte with direct database password..."
helm upgrade --install flyte-binary flyteorg/flyte-binary \
  --version ${FLYTE_VERSION:-v1.10.6} \
  --namespace ${FLYTE_NAMESPACE:-flyte} \
  --values /tmp/flyte-values-complete.yaml

echo "Flyte installation completed!"
echo "To access Flyte UI, run: ./scripts/flyte-ui.sh"
```

## Accessing Flyte UI

After deployment, use the provided `flyte-ui.sh` script to set up port forwarding and access the Flyte UI:

```bash
./scripts/flyte-ui.sh
```

This script will:
1. Check if required tools are installed
2. Verify the Flyte services exist
3. Set up port forwarding from your local port 8080 to the Flyte UI service
4. Provide a URL to access the Flyte console

You can then access the Flyte UI at http://localhost:8080/console in your web browser.

## Next Steps

After deploying Flyte, you may want to:

1. Set up a Flyte project and domain
2. Register your first workflow
3. Configure authentication for production use
4. Set up a proper ingress with SSL/TLS for production access

For more information, refer to the [Flyte documentation](https://docs.flyte.org/).

## Tearing Down Infrastructure

When you want to tear down your Flyte deployment and associated infrastructure to save costs, follow these steps:

### 1. Remove Flyte Deployment

```bash
# Delete the Flyte Helm release
helm uninstall flyte-binary -n flyte

# Delete the Flyte namespace (this will delete all resources in the namespace including K8s secrets)
kubectl delete namespace flyte
```

### 2. Remove AWS Resources

#### AWS Secrets Manager

```bash
# Delete the database password secret from AWS Secrets Manager (immediate deletion with no recovery)
aws secretsmanager delete-secret \
  --secret-id ${DB_PASSWORD_SECRET} \
  --force-delete-without-recovery
```

#### S3 Buckets (if they should be deleted)

```bash
# Empty and delete metadata bucket
aws s3 rm s3://${METADATA_BUCKET} --recursive
aws s3api delete-bucket --bucket ${METADATA_BUCKET}

# Empty and delete user data bucket
aws s3 rm s3://${USERDATA_BUCKET} --recursive
aws s3api delete-bucket --bucket ${USERDATA_BUCKET}
```

#### Database (if using a dedicated RDS instance for Flyte)

```bash
# If you created a dedicated RDS instance for Flyte, you might want to delete it
# WARNING: This will delete all data in the database
aws rds delete-db-instance \
  --db-instance-identifier ${DB_INSTANCE_ID} \
  --skip-final-snapshot \
  --delete-automated-backups
```

#### IAM Roles (if no longer needed)

```bash
# Delete IAM roles created specifically for Flyte
aws iam delete-role --role-name ${FLYTE_BACKEND_ROLE_NAME}
aws iam delete-role --role-name ${FLYTE_USER_ROLE_NAME}
```

### 3. Verification

After teardown, verify that all resources have been properly deleted:

```bash
# Verify Kubernetes resources are gone
kubectl get all -n flyte

# Verify AWS Secrets
aws secretsmanager list-secrets | grep flyte

# Verify S3 buckets
aws s3 ls | grep flyte

# Verify IAM roles
aws iam list-roles | grep flyte
```

> **Important**: Some AWS resources may have deletion protection enabled or dependencies that prevent immediate deletion. Additional steps might be required in these cases. Always review AWS console after running deletion commands to ensure resources are properly removed.

> **Warning**: The above commands will permanently delete resources and data. Make sure to back up any important data before proceeding with deletion.
