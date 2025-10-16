# ExamX-V2 Backend Deployment

This repository contains Kubernetes configuration and CI/CD workflows for deploying the ExamX-V2 backend applications across multiple environments (development, staging, and production).

## Documentation

- **[KEDA_CONFIGURATION.md](KEDA_CONFIGURATION.md)** - Complete guide for KEDA installation, configuration, and troubleshooting
- **[FEATURE_ENVIRONMENTS.md](FEATURE_ENVIRONMENTS.md)** - Feature-specific environment configurations
- **[README.md](README.md)** - This file, containing deployment overview and CI/CD workflows

## Repository Structure

```
ExamX-V2-Backend-Deployment/
├── .github/workflows/            # CI/CD workflows for automated deployments
│   ├── ci-cd-dev.yaml            # Development environment workflow
│   ├── cd-stg.yaml               # Staging environment workflow
│   └── cd-prod.yaml              # Production environment workflow
│
├── k8s/                          # Kubernetes configuration files
│   ├── base/                     # Base configurations shared across environments
│   │   ├── autoscaling/          # HorizontalPodAutoscaler configurations
│   │   ├── configmap/            # ConfigMap resources (nginx, etc.)
│   │   ├── deployment/           # Deployment resources for all services
│   │   ├── ingress/              # Ingress resources for network routing
│   │   ├── keda/                 # KEDA ScaledObject configurations
│   │   ├── pdb/                  # PodDisruptionBudget resources
│   │   ├── secret/               # Secret resources
│   │   ├── secrets/              # External secret configurations
│   │   ├── services/             # Service resources
│   │   └── kustomization.yaml    # Base kustomization file
│   │
│   └── overlays/                 # Environment-specific configurations
│       ├── dev/                  # Development environment
│       ├── stg/                  # Staging environment
│       └── prod/                 # Production environment
│
├── KEDA_CONFIGURATION.md         # KEDA installation and configuration guide
├── FEATURE_ENVIRONMENTS.md       # Feature environment setup guide
└── README.md                     # This file
```

## Application Architecture

The ExamX-V2 Backend deployment is built on a microservices architecture consisting of the following components:

- **Backend API Service**: Django-based Python application serving REST API endpoints
  - Runs on Nginx + Gunicorn for optimal performance
  - Handles HTTP requests and API operations
  - Uses PostgreSQL for data persistence (configured via environment variables)

- **Celery Workers**: Asynchronous task processing system
  - Processes background tasks separately from web requests
  - Configured with concurrency settings based on environment
  - Dedicated worker instances for different task types

- **Celery Beat**: Scheduled task management
  - Manages periodic tasks and scheduled operations
  - Shares codebase with main application and workers
  - Single instance per environment for scheduling consistency

- **Redis**: In-memory data store (optional)
  - Used for caching and message broker
  - Configurable for high availability in production

## Technical Configuration

### Nginx Configuration

The application uses Nginx as a reverse proxy with the following features:

- HTTP/HTTPS traffic management
- Request validation for API endpoints
- Content type validation for security
- Custom error handling for API responses
- Static file serving
- Buffer size optimizations
- Timeout configurations optimized for application workloads
- Gzip compression for supported content types
- Security headers (X-Frame-Options, Content-Security-Policy, etc.)
- Client certificate handling for mTLS

### Container Configuration

All components use the same Docker image but with different startup commands:

- **Backend API**: Starts the Django application with Gunicorn 
- **Celery Worker**: `celery -A examx worker -l debug -E`
- **Celery Beat**: `celery -A examx beat -l info`

### Storage Configuration

- Persistent Volume Claims (PVCs) are configured for each environment
- Media files (`/app/media`) are mounted on persistent storage
- Environment-specific storage classes for different performance needs

## CI/CD Workflows

The deployment process is managed through GitHub Actions workflows configured for each environment.

### Development Workflow (`ci-cd-dev.yaml`)

The development workflow is the simplest of the three, designed for frequent deployments with minimal approval steps:

1. **Trigger**: Manual workflow dispatch with required inputs:
   - `image`: Docker image to deploy (from ECR)
   - `sha`: Git SHA of the commit

2. **Deployment Process**:
   - Updates the image tags in Kubernetes deployment files
   - Commits changes to the repository
   - Applies Kubernetes configuration to the dev environment
   - Sends Slack notification on completion

3. **Environment**: 
   - Uses the `dev` GitHub environment
   - Deploys to `dev-stg-cluster` EKS cluster
   - Applies configuration from `k8s/overlays/dev`

4. **Security**: 
   - Minimal security controls (suitable for dev environment)
   - Requires AWS credentials for deployment

### Staging Workflow (`cd-stg.yaml`)

The staging workflow includes more controls for validation before production:

1. **Trigger**: Manual workflow dispatch with required inputs:
   - `deploy_password`: Password protection for staging deployment
   - `full_deployment`: Boolean to build new images or just deploy existing ones
   - `deploy_branch`: Branch from backend repository to deploy

2. **Security Check**:
   - Validates the deployment password
   - Sends Slack alerts on failed authentication
   - Blocks deployment if password verification fails

3. **Conditional Build Process** (if `full_deployment=true`):
   - Checks out the specified branch from backend repository
   - Sets up Docker Buildx with optimizations
   - Creates a timestamped staging image tag (`stg-YYYYMMDD-HHMMSS-commit-id`)
   - Builds and pushes Docker image to ECR
   - Caches Docker layers for faster builds

4. **Deployment Process**:
   - Updates image tags in Kubernetes deployment files
   - Commits changes to the repository
   - Applies Kubernetes configuration to the staging environment
   - Sends Slack notification on completion

5. **Environment**: 
   - Uses the staging GitHub environment
   - Deploys to `dev-stg-cluster` EKS cluster
   - Applies configuration from `k8s/overlays/stg`

### Production Workflow (`cd-prod.yaml`)

The production workflow has the most comprehensive security and validation:

1. **Trigger**: Manual workflow dispatch with required inputs:
   - `deploy_password`: Password protection for production deployment
   - `full_deployment`: Boolean to build new images or just deploy existing ones

2. **Security Check**:
   - Validates the deployment password with stronger validation
   - Sends detailed Slack alerts on unauthorized attempts
   - Blocks deployment if password verification fails

3. **Conditional Build Process** (if `full_deployment=true`):
   - Checks out the main branch from backend repository
   - Sets up Docker Buildx with production optimizations
   - Creates a timestamped production image tag (`prod-YYYYMMDD-HHMMSS-commit-id`)
   - Builds and pushes Docker image to ECR
   - Caches Docker layers for faster builds

4. **Deployment Process**:
   - Updates image tags in Kubernetes deployment files
   - Commits changes to the repository
   - Runs explicit validation with `kubectl apply --validate=true`
   - Applies Kubernetes configuration to the production environment
   - Sends comprehensive Slack notification on completion

5. **Environment**: 
   - Uses the production GitHub environment with required approvals
   - Deploys to `greatify-production-cluster` EKS cluster
   - Applies configuration from `k8s/overlays/prod`
   - Includes additional validation steps

## Deployment Environments

### Development Environment (dev)

The development environment is configured with the following characteristics:

- **Namespace**: `dev-examxv2`
- **Service Account**: `dev-examxv2-sa`
- **Resource Configuration**:
  - Backend: 1 CPU, 4Gi Memory (requests) / 2 CPU, 8Gi Memory (limits)
  - Celery Worker: 1 CPU, 4Gi Memory (requests) / 2 CPU, 6Gi Memory (limits)
  - Celery Beat: 1 CPU, 4Gi Memory (requests) / 2 CPU, 6Gi Memory (limits)
- **Replicas**: 1 for each component (no redundancy)
- **Workers**: 2 workers for the backend application
- **Secrets**: Uses AWS Secrets Manager (`arn:aws:secretsmanager:ap-south-1:399600302704:secret:examxv2-secrets-1uLP4S`)
- **Storage**: Includes PV and PVC for persistent storage
- **Environment Labels**: `environment: development`, `tier: dev`

### Staging Environment (stg)

The staging environment is configured with the following characteristics:

- **Namespace**: `stg-examxv2`
- **Service Account**: `examxv2-stg-secret-service`
- **Resource Configuration**:
  - Backend: 2 CPU, 8Gi Memory (requests) / 4 CPU, 16Gi Memory (limits)
  - Celery Worker: 1 CPU, 4Gi Memory (requests) / 2 CPU, 8Gi Memory (limits)
  - Celery Beat: 1 CPU, 4Gi Memory (requests) / 2 CPU, 8Gi Memory (limits)
- **Replicas**: 1 for each component
- **Workers**: 4 workers for the backend application
- **Ingress**: Configured with SSL certificates for `examx.co` domain
  - Certificate ARN: `arn:aws:acm:ap-south-1:399600302704:certificate/3ac85857-f810-414f-903b-1ab46d8e1520`
  - TLS client verification configured
- **Secrets**: Uses AWS Secrets Manager (`arn:aws:secretsmanager:ap-south-1:399600302704:secret:examxv2-stage-secrets-DKS1E3`)
- **Storage**: Includes PV and PVC for persistent storage
- **Environment Labels**: `environment: staging`, `tier: stg`

### Production Environment (prod)

The production environment is configured with the following characteristics:

- **Namespace**: `examxv2-production`
- **Service Account**: `examxv2-production-sa`
- **Resource Configuration**:
  - Backend: 2 CPU, 8Gi Memory (requests) / 4 CPU, 16Gi Memory (limits)
  - Celery Worker: 1 CPU, 4Gi Memory (requests) / 2 CPU, 8Gi Memory (limits)
  - Celery Beat: 1 CPU, 4Gi Memory (requests) / 2 CPU, 8Gi Memory (limits)
- **Replicas**: 2 for backend, 1 each for Celery Worker and Beat
- **Workers**: 4 workers for the backend application
- **Autoscaling**:
  - Backend: Min 2 replicas, up to 20 max replicas
  - Celery Worker: Min 2 replicas, up to 20 max replicas
  - Redis: Min 1 replica, up to 5 max replicas
- **Ingress**: Configured with SSL certificates for `examx.ai` domain
  - Certificate ARN: `arn:aws:acm:ap-south-1:399600302704:certificate/29c7b407-7f44-4060-ab94-602a60d331a5`
  - TLS client verification configured
- **Secrets**: Uses AWS Secrets Manager (`arn:aws:secretsmanager:ap-south-1:399600302704:secret:examxv2-prod-nmQjmP`)
- **Storage**: Includes PV, PVC, and custom StorageClass for persistent storage
- **Environment Labels**: `environment: production`, `tier: prod`
- **Security**: Production deployment requires password verification

## Security Features

### Secret Management

- **AWS Secrets Manager**: All sensitive configuration is stored in AWS Secrets Manager
- **CSI Driver Integration**: Secrets are mounted at runtime using the CSI driver
- **Environment Variables**: Secrets are loaded as environment variables through `.env` file
- **Service Accounts**: Environment-specific service accounts with limited permissions

### Network Security

- **TLS Termination**: SSL/TLS certificates for secure communication
- **Client Certificate Authentication**: Optional mTLS for service-to-service communication
- **Custom Headers**: Security headers to prevent common web vulnerabilities
- **Content Type Validation**: API endpoints validate correct Content-Type headers

### Deployment Security

- **Password Protection**: Production deployments require password verification
- **Slack Alerts**: Security notifications for deployment events and failures
- **Rolling Updates**: Zero-downtime deployments with proper health checks
- **Kubernetes RBAC**: Role-based access control for cluster resources

## Deployment Process

### Development Deployment

Development deployments are triggered manually with specified Docker image and Git SHA:

1. Workflow is triggered via GitHub Actions manual dispatch
2. Docker image tag is specified by the user
3. Kubernetes manifests are updated with the new image tag
4. Configuration is applied to the EKS cluster in the dev namespace
5. Slack notifications are sent upon completion

```bash
# Deploy to development environment
kubectl apply -k k8s/overlays/dev
```

### Staging Deployment

Staging deployments follow a similar process with additional validations:

1. Changes are deployed to the staging environment after testing in development
2. More resources are allocated compared to development
3. Uses a dedicated staging domain and SSL certificates
4. Configuration is applied to the EKS cluster in the stg namespace

```bash
# Deploy to staging environment
kubectl apply -k k8s/overlays/stg
```

### Production Deployment

Production deployments have enhanced security and reliability features:

1. Password verification is required to trigger the deployment
2. Optional full deployment includes building a new Docker image with a production-specific tag
3. Higher resource limits and minimum replica counts for high availability
4. Enhanced autoscaling capabilities for handling production loads
5. Comprehensive Slack notifications at each stage
6. Configuration is applied to the EKS cluster in the production namespace

```bash
# Deploy to production environment
kubectl apply -k k8s/overlays/prod
```

## Monitoring and Scaling

### KEDA (Kubernetes Event-Driven Autoscaling)

ExamX-V2 uses KEDA for intelligent autoscaling of Celery workers based on Redis queue depth. This provides:

- **Queue-Based Scaling**: Workers scale based on actual task queue depth, not just CPU/memory
- **Cost Efficiency**: Scale down to minimum replicas when queues are empty
- **Responsive Scaling**: Faster reaction time to queue changes
- **Queue-Specific Scaling**: Each worker type (default, bulk upload, enrichment, AI generator) scales independently

For detailed KEDA configuration, installation steps, and troubleshooting, see **[KEDA_CONFIGURATION.md](KEDA_CONFIGURATION.md)**.

### Horizontal Pod Autoscaling

All components are configured with Horizontal Pod Autoscalers:
- CPU Utilization: Scale up at 70% utilization
- Memory Utilization: Scale up at 80% utilization
- Min Replicas: Varies by environment (higher in production)
- Max Replicas: Up to 20 pods for production

### Scale-Down Behavior

- **Stabilization Window**: 300 seconds (5 minutes) to prevent thrashing
- **Scale-Down Policy**: 100% reduction every 15 seconds
- **Scale-Up Policy**: 70% increase or 4 pods every 15 seconds

## Maintenance and Troubleshooting

### Viewing Logs

```bash
# Backend application logs
kubectl logs -f deployment/examxv2-backend -n <namespace>

# Celery worker logs
kubectl logs -f deployment/celery-worker -n <namespace>

# Celery beat logs
kubectl logs -f deployment/celery-beat -n <namespace>
```

### Checking Deployment Status

```bash
# View all resources in namespace
kubectl get all -n <namespace>

# Check pod status
kubectl get pods -n <namespace>

# Check autoscaler status
kubectl get hpa -n <namespace>
```

### Accessing the Application Shell

```bash
# Get a shell in the backend pod
kubectl exec -it deployment/examxv2-backend -n <namespace> -- /bin/bash

# Run Django management commands
kubectl exec -it deployment/examxv2-backend -n <namespace> -- python manage.py <command>
```
