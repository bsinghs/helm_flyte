# Flyte Application Deployment

This repository contains the application deployment configuration for Flyte on AWS EKS using Helm. This follows the GitOps pattern where infrastructure is managed separately and this repository handles the Flyte application deployment.

## 📁 Project Structure

```
flyte-app/
├── README.md                       # This file - project documentation
├── FLYTE_APPLICATION_DEPLOYMENT.md # Comprehensive deployment guide
├── terraform/                     # Terraform configuration for app deployment
│   ├── main.tf                    # Main Terraform configuration
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Output values
│   ├── providers.tf               # Provider configurations
│   ├── helm-releases.tf           # Helm chart deployments
│   └── infrastructure-data.tf     # Remote state reference (if used)
├── helm/                          # Helm values and configurations
│   ├── flyte-values.yaml         # Main Flyte configuration
│   ├── flyte-values-dev.yaml     # Development environment overrides
│   ├── flyte-values-prod.yaml    # Production environment overrides
│   └── alb-controller-values.yaml # AWS Load Balancer Controller values
├── scripts/                       # Deployment and utility scripts
│   ├── deploy.sh                  # Main deployment script
│   ├── setup-secrets.sh           # Database password setup
│   ├── port-forward.sh            # Local access script
│   ├── cleanup.sh                 # Cleanup script
│   └── check-status.sh            # Status check script
├── k8s/                          # Kubernetes manifests
│   ├── namespaces/               # Namespace definitions
│   └── secrets/                  # Secret templates
└── config/                       # Configuration files
    ├── environment.env           # Environment variables template
    └── flyte-config.yaml         # Flyte configuration template
```

## 🏗️ Prerequisites

### AWS Infrastructure (Assumed to be already deployed)
- **AWS Account**: 245966534215
- **EKS Cluster**: Running and accessible
- **RDS PostgreSQL**: Database for Flyte metadata
- **S3 Buckets**: For Flyte data storage
- **IAM Roles**: IRSA roles for Flyte services
- **VPC & Networking**: Properly configured subnets and security groups

### Required Tools
- `kubectl` configured for your EKS cluster
- `helm` v3.x installed
- `aws` CLI configured with appropriate permissions (ADFS profile)
- `terraform` (optional, for infrastructure management)

### JPMC Specific Requirements
- ADFS profile configured for AWS account 245966534215
- Access to JPMC internal networks
- IDA (ID Anywhere) integration (for future OAuth implementation)

## 🚀 Quick Start

### 1. Configure AWS Access
```bash
# Ensure your ADFS profile is active
aws sts get-caller-identity

# Update kubeconfig for your EKS cluster
aws eks update-kubeconfig --region us-east-1 --name your-cluster-name
```

### 2. Set Environment Variables
```bash
# Copy and customize the environment template
cp config/environment.env.template config/environment.env

# Edit the file with your specific values
vi config/environment.env

# Source the environment
source config/environment.env
```

### 3. Deploy Flyte
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run the deployment script
./scripts/deploy.sh
```

### 4. Access Flyte Console
```bash
# Option 1: Port forward (for development)
./scripts/port-forward.sh

# Option 2: Use ingress URL (if configured)
kubectl get ingress -n flyte
```

## 📋 Deployment Methods

### Method 1: Script-based Deployment (Recommended for Quick Start)
```bash
# Set required environment variables
export CLUSTER_NAME="your-eks-cluster-name"
export AWS_REGION="us-east-1"
export DB_HOST="your-rds-endpoint"
export DB_PASSWORD="your-db-password"
export METADATA_BUCKET="your-metadata-bucket"
export USERDATA_BUCKET="your-userdata-bucket"

# Run deployment
./scripts/deploy.sh
```

### Method 2: Terraform-based Deployment (Recommended for Production)
```bash
cd terraform

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Method 3: Manual Helm Deployment
```bash
# Add Helm repositories
helm repo add flyteorg https://flyteorg.github.io/flyte
helm repo update

# Deploy AWS Load Balancer Controller
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --values helm/alb-controller-values.yaml

# Deploy Flyte
helm upgrade --install flyte-binary flyteorg/flyte-binary \
  --namespace flyte \
  --create-namespace \
  --values helm/flyte-values.yaml
```

## 🔧 Configuration

### Environment Variables
The deployment uses the following key environment variables:

```bash
# AWS Configuration
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="245966534215"

# EKS Configuration
CLUSTER_NAME="your-eks-cluster-name"

# Database Configuration
DB_HOST="your-rds-endpoint"
DB_PORT="5432"
DB_NAME="flyteadmin"
DB_USERNAME="postgres"
DB_PASSWORD="your-secure-password"

# Storage Configuration
METADATA_BUCKET="your-flyte-metadata-bucket"
USERDATA_BUCKET="your-flyte-userdata-bucket"

# IAM Roles (IRSA)
FLYTE_BACKEND_ROLE_ARN="arn:aws:iam::245966534215:role/your-flyte-backend-role"
FLYTE_USER_ROLE_ARN="arn:aws:iam::245966534215:role/your-flyte-user-role"
ALB_CONTROLLER_ROLE_ARN="arn:aws:iam::245966534215:role/your-alb-controller-role"
```

### Flyte Configuration Highlights
- **Storage**: S3-based storage for metadata and user data
- **Database**: PostgreSQL for Flyte metadata
- **Authentication**: Disabled initially (OAuth/IDA integration planned)
- **Ingress**: AWS ALB for external access
- **Logging**: CloudWatch integration
- **RBAC**: Kubernetes RBAC with IRSA

## 🔍 Verification

### Check Deployment Status
```bash
# Check all components
./scripts/check-status.sh

# Manual checks
kubectl get pods -n flyte
kubectl get services -n flyte
kubectl get ingress -n flyte
```

### Test Flyte Installation
```bash
# Install flytectl
curl -sL https://ctl.flyte.org/install | bash

# Configure flytectl
flytectl config init --host localhost:8080  # or your ingress URL

# Test connection
flytectl version
flytectl get projects
```

## 🔐 Security Considerations

### Current Security Posture
- **Authentication**: Disabled (development mode)
- **Network**: Private subnets for EKS nodes
- **IAM**: IRSA for service accounts
- **Secrets**: Kubernetes secrets for database credentials

### Planned Security Enhancements
- **OAuth Integration**: IDA (ID Anywhere) authentication
- **RBAC**: Fine-grained role-based access control
- **Network Policies**: Kubernetes network policies
- **TLS**: End-to-end TLS encryption

## 🔄 Future OAuth Integration (IDA)

The following components are prepared for future OAuth integration:

1. **Identity Provider Configuration**: Ready for IDA integration
2. **RBAC Templates**: Prepared for user/group mapping
3. **Configuration Templates**: OAuth-ready Flyte configuration
4. **Documentation**: OAuth deployment guide

## 🧹 Cleanup

### Remove Flyte Deployment
```bash
# Run cleanup script
./scripts/cleanup.sh

# Or manual cleanup
helm uninstall flyte-binary -n flyte
kubectl delete namespace flyte
```

## 📚 Additional Resources

- [Flyte Documentation](https://docs.flyte.org/)
- [Union.ai Deployment Guide](https://www.union.ai/docs/flyte/deployment/flyte-deployment/installing/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Helm Documentation](https://helm.sh/docs/)

## 🆘 Troubleshooting

### Common Issues
1. **AWS Authentication**: Ensure ADFS profile is active
2. **Database Connection**: Check RDS security groups
3. **S3 Access**: Verify IAM roles and bucket policies
4. **Ingress Issues**: Check AWS Load Balancer Controller

### Getting Help
1. Check logs: `kubectl logs -n flyte deployment/flyte-binary`
2. Check events: `kubectl get events -n flyte`
3. Run status check: `./scripts/check-status.sh`

---

**Note**: This deployment is configured for JPMC AWS account 245966534215 with ADFS authentication. Ensure your AWS CLI is configured with the correct profile before proceeding.
