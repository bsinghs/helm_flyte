# Flyte Deployment Scripts

This directory contains scripts for deploying and managing Flyte on Kubernetes. The scripts are organized into subdirectories based on their functionality.

## Directory Structure

```
scripts/
├── core/                # Core deployment and management scripts
│   ├── setup-environment.sh  # Set up environment for Flyte deployment
│   ├── deploy.sh             # Deploy Flyte to Kubernetes
│   ├── check-status.sh       # Check status of Flyte deployment
│   ├── port-forward.sh       # Set up port forwarding to access Flyte console
│   └── cleanup.sh            # Clean up Flyte deployment
├── database/            # Database management scripts
│   ├── create-db-password.sh    # Create and manage database password
│   ├── get-db-password.sh       # Retrieve password from AWS Secrets Manager
│   └── sample-secure-deploy.sh  # Example of secure deployment practices
└── *.sh                 # Wrapper scripts that forward to subdirectories
```

## Usage

You can run the scripts directly from the main scripts directory. The wrapper scripts will automatically forward to the appropriate script in the subdirectories.

```bash
# These all work the same
./scripts/setup-environment.sh
./scripts/deploy.sh
./scripts/check-status.sh
```

## Core Scripts

These scripts handle the main deployment and management tasks:

- **setup-environment.sh**: Initializes your environment for Flyte deployment
- **deploy.sh**: Deploys Flyte to your Kubernetes cluster
- **check-status.sh**: Verifies the status of your Flyte deployment
- **port-forward.sh**: Sets up port forwarding to access the Flyte console
- **cleanup.sh**: Removes the Flyte deployment

## Database Scripts

These scripts handle database password management and security:

- **create-db-password.sh**: Creates and manages the PostgreSQL database password
- **get-db-password.sh**: Helper script to retrieve password from AWS Secrets Manager
- **sample-secure-deploy.sh**: Demonstrates secure deployment practices

## Security Note

All database passwords are stored in AWS Secrets Manager and retrieved only when needed. No sensitive information is stored in configuration files or scripts.
