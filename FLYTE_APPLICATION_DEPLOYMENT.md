# Flyte Application Deployment Guide

This document provides a comprehensive guide for deploying Flyte applications using the infrastructure outputs from the separate infrastructure repository.

## 🏗️ **Architecture Overview**

This follows a **GitOps separation** pattern:
- **Infrastructure Repository**: Provisions AWS resources (EKS, RDS, S3, IAM roles)
- **Application Repository**: Handles Flyte Helm chart deployment and configuration

## 📋 **Prerequisites**

### Infrastructure Requirements
- EKS cluster deployed via the infrastructure repository
- All Flyte infrastructure components provisioned (RDS, S3, IAM roles)
- Access to infrastructure Terraform state/outputs

### Tools Required
- `kubectl` configured for your EKS cluster
- `helm` v3.x installed
- `aws` CLI configured with appropriate permissions
- Access to infrastructure repository outputs

## 🔑 **Required Infrastructure Values**

### **Getting All Values at Once**
```bash
# From your infrastructure repository:
terraform output flyte_infrastructure_config
```

### **Individual Infrastructure Outputs**

#### **1. EKS Cluster Information**
```bash
terraform output cluster_name           # e.g., "education-eks-abc12345"
terraform output cluster_endpoint       # e.g., "https://ABC123.gr7.us-east-1.eks.amazonaws.com"
terraform output region                 # e.g., "us-east-1"
```

#### **2. Database Configuration**
```bash
terraform output flyte_database_host     # e.g., "flyte-db.abc123.us-east-1.rds.amazonaws.com"
terraform output flyte_database_port     # e.g., "5432"
terraform output flyte_database_name     # e.g., "flyteadmin"
terraform output flyte_database_username # e.g., "postgres"
# Note: Password handled separately via AWS Secrets Manager or environment variable
```

#### **3. S3 Storage Buckets**
```bash
terraform output flyte_metadata_bucket   # e.g., "flyte-metadata-abc123"
terraform output flyte_userdata_bucket   # e.g., "flyte-userdata-abc123"
```

#### **4. IAM Roles for Service Accounts (IRSA)**
```bash
terraform output flyte_backend_role_arn              # For Flyte core services
terraform output flyte_user_role_arn                 # For user workloads
terraform output aws_load_balancer_controller_role_arn # For ALB/NLB management
```

#### **5. Network Information**
```bash
terraform output vpc_id               # e.g., "vpc-abc123456"
terraform output private_subnet_ids   # For EKS node placement
terraform output public_subnet_ids    # For load balancers
```

#### **6. EKS OIDC Information (for additional IRSA roles)**
```bash
terraform output eks_oidc_provider_arn      # e.g., "arn:aws:iam::123456789012:oidc-provider/..."
terraform output eks_cluster_oidc_issuer_url # e.g., "https://oidc.eks.us-east-1.amazonaws.com/id/ABC123"
```

## 📁 **Recommended Application Repository Structure**

```
flyte-app/
├── terraform/
│   ├── infrastructure-data.tf       # Remote state reference
│   ├── helm-releases.tf             # Helm chart deployments
│   ├── variables.tf                 # App-specific variables
│   └── providers.tf                 # Terraform providers
├── helm/
│   ├── flyte-values.yaml           # Flyte Helm values
│   ├── flyte-values-dev.yaml       # Development overrides
│   ├── flyte-values-prod.yaml      # Production overrides
│   └── alb-controller-values.yaml  # AWS Load Balancer Controller values
├── scripts/
│   ├── deploy.sh                   # Main deployment script
│   ├── setup-secrets.sh            # Database password setup
│   ├── port-forward.sh             # Local access script
│   └── cleanup.sh                  # Cleanup script
├── k8s/
│   ├── namespaces/                 # Namespace definitions
│   ├── secrets/                    # Secret templates
│   └── rbac/                       # Additional RBAC if needed
└── README.md                       # Application deployment docs
```

## 🔧 **Setup Methods**

### **Method 1: Terraform Remote State (Recommended)**

#### `terraform/infrastructure-data.tf`
```hcl
# Reference infrastructure state
data "terraform_remote_state" "flyte_infrastructure" {
  backend = "s3"  # or whatever backend you're using
  config = {
    bucket = "your-terraform-state-bucket"
    key    = "flyte-infrastructure/terraform.tfstate"
    region = "us-east-1"
  }
}

# Extract configuration for easy use
locals {
  infra = data.terraform_remote_state.flyte_infrastructure.outputs.flyte_infrastructure_config
  
  # EKS Configuration
  cluster_name     = local.infra.cluster_name
  cluster_endpoint = local.infra.cluster_endpoint
  aws_region       = local.infra.aws_region
  
  # Database Configuration
  db_host     = local.infra.database.host
  db_port     = local.infra.database.port
  db_name     = local.infra.database.name
  db_username = local.infra.database.username
  
  # Storage Configuration
  metadata_bucket = local.infra.storage.metadata_bucket
  userdata_bucket = local.infra.storage.userdata_bucket
  
  # IAM Roles
  flyte_backend_role_arn = local.infra.iam_roles.flyte_backend_role_arn
  flyte_user_role_arn    = local.infra.iam_roles.flyte_user_role_arn
  alb_controller_role_arn = local.infra.iam_roles.aws_load_balancer_controller_role_arn
  
  # Network Configuration
  vpc_id             = local.infra.network.vpc_id
  private_subnet_ids = local.infra.network.private_subnet_ids
  public_subnet_ids  = local.infra.network.public_subnet_ids
}
```

#### `terraform/helm-releases.tf`
```hcl
# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.2"

  values = [
    templatefile("${path.module}/../helm/alb-controller-values.yaml", {
      cluster_name = local.cluster_name
      role_arn     = local.alb_controller_role_arn
    })
  ]

  depends_on = [
    data.terraform_remote_state.flyte_infrastructure
  ]
}

# Flyte
resource "helm_release" "flyte" {
  name       = "flyte-binary"
  repository = "https://flyteorg.github.io/flyte"
  chart      = "flyte-binary"
  namespace  = "flyte"
  version    = "v1.10.6"  # Use latest stable version

  create_namespace = true

  values = [
    templatefile("${path.module}/../helm/flyte-values.yaml", {
      # Database
      db_host     = local.db_host
      db_port     = local.db_port
      db_name     = local.db_name
      db_username = local.db_username
      
      # Storage
      metadata_bucket = local.metadata_bucket
      userdata_bucket = local.userdata_bucket
      aws_region      = local.aws_region
      
      # IAM Roles
      flyte_backend_role_arn = local.flyte_backend_role_arn
      flyte_user_role_arn    = local.flyte_user_role_arn
      
      # Cluster
      cluster_name = local.cluster_name
    })
  ]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    kubernetes_secret.flyte_db_secret
  ]
}

# Database secret
resource "kubernetes_secret" "flyte_db_secret" {
  metadata {
    name      = "flyte-db-secret"
    namespace = "flyte"
  }

  data = {
    password = var.flyte_db_password
  }

  depends_on = [
    kubernetes_namespace.flyte
  ]
}

resource "kubernetes_namespace" "flyte" {
  metadata {
    name = "flyte"
  }
}
```

### **Method 2: Manual Configuration**

#### `helm/flyte-values.yaml`
```yaml
# Flyte Configuration Template
configuration:
  database:
    username: postgres
    password: ${db_password}  # From Kubernetes secret or environment
    host: "${db_host}"
    port: ${db_port}
    dbname: "${db_name}"
    
  storage:
    # Learn more: https://docs.flyte.org/en/latest/concepts/data_management.html
    metadataContainer: "${metadata_bucket}"
    userDataContainer: "${userdata_bucket}"
    provider: s3
    providerConfig:
      s3:
        region: "${aws_region}"
        authType: "iam"
        
  # CloudWatch logging configuration
  logging:
    level: 5
    plugins:
      cloudwatch:
        enabled: true
        templateUri: |-
          https://console.aws.amazon.com/cloudwatch/home?region=${aws_region}#logEventViewer:group=/aws/eks/${cluster_name}/cluster;stream=var.log.containers.{{ .podName }}_{{ .namespace }}_{{ .containerName }}-{{ .containerId }}.log

  # Authentication (disabled by default)
  auth:
    enabled: false

  # Inline configuration for cluster resources
  inline:
    cluster_resources:
      customData:
      - production:
        - defaultIamRole:
            value: "${flyte_user_role_arn}"
      - staging:
        - defaultIamRole:
            value: "${flyte_user_role_arn}"
      - development:
        - defaultIamRole:
            value: "${flyte_user_role_arn}"
            
    flyteadmin:
      roleNameKey: "iam.amazonaws.com/role"
      
    plugins:
      k8s:
        inject-finalizer: true
        default-env-vars:
          - AWS_METADATA_SERVICE_TIMEOUT: 5
          - AWS_METADATA_SERVICE_NUM_ATTEMPTS: 20

# Cluster resource templates for namespace/service account creation
clusterResourceTemplates:
  inline:
    001_namespace.yaml: |
      apiVersion: v1
      kind: Namespace
      metadata:
        name: '{{ namespace }}'
        
    002_serviceaccount.yaml: |
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: default
        namespace: '{{ namespace }}'
        annotations:
          eks.amazonaws.com/role-arn: '{{ defaultIamRole }}'

# Service account with IRSA for Flyte backend
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: "${flyte_backend_role_arn}"

# Ingress configuration (using ALB)
ingress:
  create: true
  ingressClassName: alb
  commonAnnotations:
    alb.ingress.kubernetes.io/group.name: flyte
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS":443}]'
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/target-type: ip
  httpAnnotations:
    alb.ingress.kubernetes.io/actions.app-root: '{"Type": "redirect", "RedirectConfig": {"Path": "/console", "StatusCode": "HTTP_302"}}'
  grpcAnnotations:
    alb.ingress.kubernetes.io/backend-protocol-version: GRPC
  # host: flyte.yourdomain.com  # Set your domain here
```

#### `helm/alb-controller-values.yaml`
```yaml
clusterName: ${cluster_name}

serviceAccount:
  create: true
  name: aws-load-balancer-controller
  annotations:
    eks.amazonaws.com/role-arn: "${role_arn}"

# AWS Load Balancer Controller configuration
replicaCount: 2

# Resource limits
resources:
  limits:
    cpu: 200m
    memory: 500Mi
  requests:
    cpu: 100m
    memory: 200Mi

# Pod disruption budget
podDisruptionBudget:
  maxUnavailable: 1

# Node selector (optional)
nodeSelector:
  kubernetes.io/os: linux
```

## 🔐 **Database Password Management**

### **Option 1: AWS Secrets Manager (Recommended)**
```bash
# Store password in Secrets Manager
aws secretsmanager create-secret \
  --name "flyte-db-password" \
  --description "Flyte database password" \
  --secret-string "your-secure-password"

# Retrieve in deployment
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "flyte-db-password" \
  --query SecretString --output text)
```

### **Option 2: Kubernetes Secret**
```bash
# Create secret directly in cluster
kubectl create secret generic flyte-db-secret \
  --from-literal=password="your-secure-password" \
  --namespace=flyte
```

### **Option 3: Environment Variable**
```bash
export FLYTE_DB_PASSWORD="your-secure-password"
```

## 🚀 **Deployment Scripts**

### `scripts/deploy.sh`
```bash
#!/bin/bash
set -e

echo "🚀 Starting Flyte deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
print_status "Checking prerequisites..."
for cmd in kubectl helm aws terraform; do
    if ! command -v $cmd &> /dev/null; then
        print_error "$cmd is required but not installed"
        exit 1
    fi
done

# Get infrastructure configuration
print_status "Getting infrastructure configuration..."
cd terraform
terraform init -input=false
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw region 2>/dev/null || echo "")
cd ..

if [[ -z "$CLUSTER_NAME" || -z "$AWS_REGION" ]]; then
    print_error "Could not get infrastructure configuration. Make sure terraform outputs are available."
    exit 1
fi

print_status "Cluster: $CLUSTER_NAME, Region: $AWS_REGION"

# Configure kubectl
print_status "Configuring kubectl..."
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Test cluster connectivity
print_status "Testing cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# Add Helm repositories
print_status "Adding Helm repositories..."
helm repo add flyteorg https://flyteorg.github.io/flyte
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Deploy AWS Load Balancer Controller
print_status "Deploying AWS Load Balancer Controller..."
if ! kubectl get deployment -n kube-system aws-load-balancer-controller &> /dev/null; then
    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --values helm/alb-controller-values.yaml \
        --wait
else
    print_status "AWS Load Balancer Controller already installed"
fi

# Create Flyte namespace
print_status "Creating Flyte namespace..."
kubectl create namespace flyte --dry-run=client -o yaml | kubectl apply -f -

# Handle database password
if [[ -z "$FLYTE_DB_PASSWORD" ]]; then
    print_warning "FLYTE_DB_PASSWORD not set. Attempting to retrieve from AWS Secrets Manager..."
    FLYTE_DB_PASSWORD=$(aws secretsmanager get-secret-value \
        --secret-id "flyte-db-password" \
        --query SecretString --output text 2>/dev/null || echo "")
    
    if [[ -z "$FLYTE_DB_PASSWORD" ]]; then
        print_error "Database password not found. Set FLYTE_DB_PASSWORD or store in AWS Secrets Manager."
        exit 1
    fi
fi

# Create database secret
print_status "Creating database secret..."
kubectl create secret generic flyte-db-secret \
    --from-literal=password="$FLYTE_DB_PASSWORD" \
    --namespace=flyte \
    --dry-run=client -o yaml | kubectl apply -f -

# Deploy Flyte
print_status "Deploying Flyte..."
helm upgrade --install flyte-binary flyteorg/flyte-binary \
    --namespace flyte \
    --values helm/flyte-values.yaml \
    --wait \
    --timeout 10m

# Wait for pods to be ready
print_status "Waiting for Flyte pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=flyte-binary -n flyte --timeout=300s

# Get access information
print_status "Getting access information..."
kubectl get services -n flyte
kubectl get ingress -n flyte 2>/dev/null || print_warning "No ingress found"

print_status "✅ Flyte deployment completed successfully!"

echo ""
echo "🎯 Next Steps:"
echo "1. Check status: kubectl get pods -n flyte"
echo "2. Access Flyte Console via the ingress URL or port-forward:"
echo "   kubectl port-forward -n flyte service/flyte-binary 8080:8080"
echo "   Then visit: http://localhost:8080/console"
echo "3. Install flytectl: https://docs.flyte.org/en/latest/flytectl/index.html"
```

### `scripts/setup-secrets.sh`
```bash
#!/bin/bash
set -e

echo "🔐 Setting up Flyte secrets..."

# Check if password is provided
if [[ -z "$1" ]]; then
    echo "Usage: $0 <database-password>"
    echo "Or set FLYTE_DB_PASSWORD environment variable"
    exit 1
fi

DB_PASSWORD="$1"

# Store in AWS Secrets Manager
echo "Storing password in AWS Secrets Manager..."
aws secretsmanager create-secret \
    --name "flyte-db-password" \
    --description "Flyte database password" \
    --secret-string "$DB_PASSWORD" 2>/dev/null || \
aws secretsmanager update-secret \
    --secret-id "flyte-db-password" \
    --secret-string "$DB_PASSWORD"

echo "✅ Password stored in AWS Secrets Manager"

# Create Kubernetes secret
echo "Creating Kubernetes secret..."
kubectl create namespace flyte --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic flyte-db-secret \
    --from-literal=password="$DB_PASSWORD" \
    --namespace=flyte \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Kubernetes secret created"
echo "🎯 You can now run the deployment script"
```

### `scripts/port-forward.sh`
```bash
#!/bin/bash
echo "🌐 Setting up port forwarding to Flyte Console..."
echo "Flyte Console will be available at: http://localhost:8080/console"
echo "Press Ctrl+C to stop port forwarding"
kubectl port-forward -n flyte service/flyte-binary 8080:8080
```

## 🔍 **Verification and Testing**

### **Check Deployment Status**
```bash
# Check all Flyte pods
kubectl get pods -n flyte

# Check Flyte services
kubectl get services -n flyte

# Check ingress (if using ALB)
kubectl get ingress -n flyte

# Check AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### **Access Flyte Console**
```bash
# Option 1: Via Ingress (if configured)
kubectl get ingress -n flyte

# Option 2: Via Port Forward
kubectl port-forward -n flyte service/flyte-binary 8080:8080
# Then visit: http://localhost:8080/console

# Option 3: Via LoadBalancer
kubectl get service -n flyte flyte-binary
```

### **Test Flyte Workflow**
```bash
# Install flytectl
curl -sL https://ctl.flyte.org/install | bash

# Configure flytectl
flytectl config init --host localhost:8080  # or your ingress URL

# Check Flyte status
flytectl version

# List projects
flytectl get projects
```

## 🧹 **Cleanup**

### `scripts/cleanup.sh`
```bash
#!/bin/bash
echo "🧹 Cleaning up Flyte deployment..."

# Remove Flyte
helm uninstall flyte-binary -n flyte || true

# Remove AWS Load Balancer Controller
helm uninstall aws-load-balancer-controller -n kube-system || true

# Remove namespaces
kubectl delete namespace flyte || true

# Remove secrets from AWS Secrets Manager
aws secretsmanager delete-secret --secret-id "flyte-db-password" --force-delete-without-recovery || true

echo "✅ Cleanup completed"
```

## 📚 **Additional Resources**

- [Flyte Documentation](https://docs.flyte.org/)
- [Flyte on EKS Guide](https://docs.flyte.org/en/latest/deployment/aws/index.html)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Helm Documentation](https://helm.sh/docs/)
- [EKS IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)

## 🔧 **Troubleshooting**

### **Common Issues**
1. **Database Connection**: Check security groups and VPC configuration in infrastructure
2. **S3 Access**: Verify IAM roles and bucket policies
3. **Ingress Issues**: Ensure AWS Load Balancer Controller is installed and healthy
4. **Pod Failures**: Check CloudWatch logs and kubectl logs

### **Useful Commands**
```bash
# Check Flyte logs
kubectl logs -n flyte deployment/flyte-binary

# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Describe problematic pods
kubectl describe pod -n flyte <pod-name>

# Check events
kubectl get events -n flyte --sort-by='.lastTimestamp'
```

---

This guide provides everything needed to deploy Flyte applications using the infrastructure from your separate infrastructure repository. Keep this as a reference for your application deployment repository! 🚀
