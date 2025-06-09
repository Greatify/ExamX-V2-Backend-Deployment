# UAT Environment Setup

## Overview
This document describes the UAT (User Acceptance Testing) environment setup for ExamX-V2 Backend deployment.

## UAT Environment Specifications

### Namespace
- **Namespace**: `uat-examxv2`
- **Environment**: UAT
- **Cluster**: `dev-stg-cluster`

### Service Account
- **Service Account**: `examxv2-stg-secret-service`
- **Namespace**: `uat-examxv2`

### Secrets Configuration  
- **Secret Name**: `examxv2-backend-uat`
- **Secret ARN**: `arn:aws:secretsmanager:ap-south-1:399600302704:secret:examxv2-backend-uat-9G4vRf`
- **Secret Provider**: AWS Secrets Manager

### Storage Configuration
- **PVC**: Not configured (completely removed as per requirement)
- **EFS**: Not used in UAT environment
- **Persistent Volumes**: Not used in UAT environment
- **Volume Mounts**: Only secrets and config volumes, no persistent storage

### Resource Allocation

#### Backend Deployment
- **Replicas**: 1
- **CPU Request**: 1 core
- **Memory Request**: 4Gi  
- **CPU Limit**: 2 cores
- **Memory Limit**: 8Gi
- **Workers**: 2

#### Celery Worker
- **Replicas**: 1
- **CPU Request**: 500m
- **Memory Request**: 2Gi
- **CPU Limit**: 1 core  
- **Memory Limit**: 4Gi

#### Celery Beat
- **Replicas**: 1
- **CPU Request**: 500m
- **Memory Request**: 2Gi
- **CPU Limit**: 1 core
- **Memory Limit**: 4Gi

### Ingress Configuration
- **Domain**: `klockwork.ai`
- **CORS Origins**: `https://klockwork.ai,https://www.klockwork.ai,https://*.klockwork.ai`
- **Certificate ARN**: `arn:aws:acm:ap-south-1:399600302704:certificate/3ac85857-f810-414f-903b-1ab46d8e1520`

## Deployment Workflow

### Workflow: Deploy to UAT (`cd-uat.yaml`)

#### Trigger
The UAT deployment is triggered via **workflow_dispatch** (manual trigger) with the following inputs:

1. **deploy_password**: Required deployment password for security
2. **full_deployment**: Boolean to determine if new images should be built
3. **deploy_branch**: Branch name to deploy from

#### Jobs

1. **Security Password Check**
   - Verifies deployment password
   - Sends alerts on unauthorized attempts
   - Blocks deployment on invalid password

2. **Build Backend UAT Image** (if full_deployment = true)
   - Builds Docker image from specified branch
   - Tags image with `uat-{timestamp}-{commit_id}` format
   - Pushes to ECR repository
   - Caches Docker layers for optimization

3. **Deploy Backend UAT**
   - Updates image tags in deployment files (if new build)
   - Deploys to UAT namespace using Kustomize
   - Verifies deployment status
   - Sends Slack notifications

### How to Deploy

1. Go to GitHub Actions in the ExamX-V2-Backend-Deployment repository
2. Select "Deploy to UAT" workflow
3. Click "Run workflow"
4. Fill in the required parameters:
   - **deploy_password**: Enter the deployment password
   - **full_deployment**: Check if you want to build new images
   - **deploy_branch**: Enter the branch name to deploy
5. Click "Run workflow" to start the deployment

### Environment Variables Required

Make sure the following secrets are configured in the `uat` environment:

- `DEPLOY_PASSWORD`: Password for deployment security
- `AWS_ACCESS_KEY_ID`: AWS access key for ECR and EKS
- `AWS_SECRET_ACCESS_KEY`: AWS secret key
- `AWS_REGION`: AWS region (ap-south-1)
- `REPO_DISPATCH_TOKEN`: GitHub token for repository access
- `SLACK_WEBHOOK_URL`: Slack webhook for notifications

## Key Differences from Staging

1. **No PVC/PV**: UAT environment doesn't use persistent volume claims
2. **Lower Resources**: Reduced CPU and memory allocation for cost optimization
3. **UAT-specific Secrets**: Uses `examxv2-backend-uat` secret
4. **UAT Domain**: Uses `klockwork.ai` domain
5. **Reduced Workers**: Only 2 backend workers vs 4 in staging

## Manual Deployment Commands

If you need to deploy manually:

```bash
# Configure kubectl
aws eks update-kubeconfig --name dev-stg-cluster --region ap-south-1

# Deploy to UAT
kubectl apply -k k8s/overlays/uat

# Check deployment status
kubectl get deployments -n uat-examxv2
kubectl get pods -n uat-examxv2

# Check service account
kubectl get sa -n uat-examxv2
```

## Troubleshooting

### Common Issues

1. **Service Account Not Found**
   ```bash
   kubectl get sa -n uat-examxv2
   # Should show: examxv2-stg-secret-service
   ```

2. **Secret Provider Class Issues**
   ```bash
   kubectl describe secretproviderclass examxv2-backend-secrets -n uat-examxv2
   ```

3. **Pod Not Starting**
   ```bash
   kubectl describe pods -n uat-examxv2
   kubectl logs -f deployment/examxv2-backend -n uat-examxv2
   ```

### Verification Steps

1. Check namespace exists:
   ```bash
   kubectl get namespace uat-examxv2
   ```

2. Verify deployments are running:
   ```bash
   kubectl get deployments -n uat-examxv2
   ```

3. Check service account permissions:
   ```bash
   kubectl get sa examxv2-stg-secret-service -n uat-examxv2 -o yaml
   ```

4. Verify secret mounting:
   ```bash
   kubectl get secretproviderclass -n uat-examxv2
   ```

## Monitoring and Logs

- **Deployment Status**: Check via kubectl or AWS EKS console
- **Application Logs**: Available via kubectl logs
- **Slack Notifications**: Configured for deployment success/failure
- **GitHub Actions**: Full deployment logs available in Actions tab

## Contact

For issues with UAT deployment, contact:
- DevOps Team
- Hariharen (hariharen@greatify.ai) 