# Flyte Database and Environment Setup

This document explains the setup process for connecting to the PostgreSQL database in AWS and managing environment configuration securely.

## What We've Done So Far

### 1. Database Access and Configuration

#### The Database Setup
- **AWS RDS Instance**: We're using an existing PostgreSQL RDS instance called `education-eks-vv8vcaqw-flyte-db` in AWS
- **Location**: The database is inside a VPC in your AWS account
- **Security**: The database is only accessible from within the VPC (10.0.0.0/16 network)

#### How We Access the Database
There are two ways to access the database:

1. **From within the Kubernetes (EKS) cluster**:
   - Pods running in the EKS cluster can connect directly to the RDS instance
   - We tested this using a temporary PostgreSQL pod: `kubectl run pg-test --image=postgres:14`

2. **From your local machine**:
   - Direct connection is NOT possible because your local machine isn't in the AWS VPC
   - We created a "tunnel" using Kubernetes to connect from your local machine to the database
   - This is done using the `kubectl port-forward` command which creates a secure tunnel

### 2. Password Management

#### How We Handle the Database Password:

We've implemented a secure approach to manage the database password:

1. **Initial Setup**:
   - Created a random, secure password
   - Stored it in AWS Secrets Manager as `flyte-db-password`
   - Updated the actual RDS database to use this password
   
2. **Secure Access**:
   - The password is NOT stored in your config files
   - Instead, we retrieve it from AWS Secrets Manager only when needed
   - The environment file only stores a reference to the secret name
   
3. **Helper Script**:
   - Created `get-db-password.sh` to retrieve the password securely from AWS Secrets Manager
   - This script can be sourced by other scripts to use the password temporarily

### 3. Environment Configuration

#### The Environment File:

- Located at `config/environment.env`
- Contains all configuration values needed for Flyte deployment
- Includes references to:
  - AWS resources (region, account ID)
  - EKS cluster information
  - Database connection details
  - Storage bucket names
  - IAM roles
  - Resource requirements

#### What Makes This Approach Secure:

- Sensitive information (database password) is stored in AWS Secrets Manager
- Only references to secrets are stored in configuration files
- Temporary secrets are retrieved at runtime and not persisted
- Scripts unset sensitive environment variables after use

## The Commands We Used

### Creating a Database Tunnel

```bash
# This creates a secure tunnel from your local machine to the database in AWS
kubectl run pg-test --image=postgres:14 --rm -it --env=PGPASSWORD=$DB_PASSWORD \
  --command -- psql -h education-eks-vv8vcaqw-flyte-db.cdhzgmmntzio.us-east-1.rds.amazonaws.com \
  -U postgres -d flyteadmin
```

What this does:
- Creates a temporary pod in your Kubernetes cluster
- Sets up the PostgreSQL client (psql) inside the pod
- Establishes a connection to the RDS database
- Forwards the connection back to your terminal
- Automatically cleans up when you exit

### Setting Up Secure Password Handling

```bash
# Generate a secure password and store it in AWS Secrets Manager
./scripts/create-db-password.sh

# Retrieve the password when needed
source ./scripts/get-db-password.sh
DB_PASSWORD=$(get_db_password "flyte-db-password")
```

## Why We Did This

1. **Security**: To keep sensitive information out of configuration files and git repositories
2. **Access Control**: To enable secure access to a database that's in a private VPC
3. **Best Practices**: To follow cloud-native security principles
4. **Automation**: To make it easy to deploy and manage Flyte without manual steps

## Next Steps

1. **Deploy Flyte**: Use `./scripts/deploy.sh` to deploy Flyte to your EKS cluster
2. **Access Flyte Console**: After deployment, use `./scripts/port-forward.sh` to access the Flyte console
3. **Check Status**: Use `./scripts/check-status.sh` to verify the deployment status

## Tips for Database Access

- When testing database connection from your local machine, always use `kubectl port-forward` or a similar tunneling method
- For applications running inside the cluster, use the direct database hostname 
- Always retrieve secrets at runtime, don't store them in files
- Use Kubernetes secrets for applications that need database access

Remember: The actual database password is stored securely in AWS Secrets Manager and is only retrieved when needed. This keeps your deployment secure while making it easy to manage.
