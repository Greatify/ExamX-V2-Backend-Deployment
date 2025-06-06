# Feature Environment Workflow

This document explains how to deploy and manage feature environments for the ExamX-V2 Backend project.

## Overview

Feature environments allow developers to deploy their feature branches to temporary environments for testing and demo purposes. These environments are manually managed and cleaned up when no longer needed.

## Architecture

- **Namespace**: Each feature environment gets its own Kubernetes namespace (`feat-{branch-name}-examxv2`)
- **Subdomain**: Each environment is accessible via `https://{branch-name}.examx.cloud`
- **Resources**: Feature environments use reduced resource allocations to optimize costs
- **Cleanup**: Manual cleanup when developers no longer need the environment
- **Environment Types**: Default secrets OR custom .env content

## How to Deploy a Feature Environment

### 1. Via GitHub Actions (Recommended)

1. Go to the **ExamX-V2-Backend** repository
2. Navigate to **Actions** → **ExamX-V2 Backend CI - Feature Branch**
3. Click **Run workflow**
4. Fill in the parameters:
   - **Branch name**: Your feature branch name (e.g., `feature/user-authentication`)
   - **Custom .env content** (Optional): Paste your custom .env file content
5. Click **Run workflow**

### 2. Custom Environment Variables

#### Option A: Default Dev Secrets (Recommended)
- Leave the "Custom .env content" field empty
- Uses the same secrets as the dev environment
- Fastest deployment option

#### Option B: Custom .env Content
- Paste your complete .env file content in the "Custom .env content" field
- Perfect for testing specific configurations
- Examples of what you can customize:
  ```env
  DEBUG=True
  DATABASE_URL=postgresql://custom_db_url
  REDIS_URL=redis://custom_redis_url
  API_KEY=your_test_api_key
  FEATURE_FLAG_NEW_UI=true
  ```

### 3. Workflow Process

The deployment process involves two workflows:

#### CI Workflow (`ci-feat.yaml`)
- Validates inputs (branch name, custom .env)
- Builds Docker image from your feature branch
- Pushes image to ECR with feature-specific tag
- Encodes custom .env content securely
- Triggers deployment workflow

#### CD Workflow (`cd-feat.yaml`)
- Creates dynamic Kubernetes namespace
- Generates environment-specific configurations
- Creates ConfigMap for custom .env (if provided)
- Deploys backend, Celery worker, and beat services
- Sets up ingress with unique subdomain
- Sends Slack notifications with access URL

## Environment Details

### Resource Allocation

Feature environments use reduced resources:

- **Backend**: 0.5-1 CPU, 2-4Gi RAM
- **Celery Worker**: 0.25-0.5 CPU, 1-2Gi RAM  
- **Celery Beat**: 0.1-0.25 CPU, 512Mi-1Gi RAM

### Environment Variables

Additional environment variables set for feature environments:
- `DJANGO_DEBUG=True`
- `FEATURE_ENV=true`
- `BRANCH_NAME={your-branch-name}`
- `WORKERS=1`
- `ENV_TYPE=custom` or `ENV_TYPE=default`

### Environment Types

#### Default Environment
- Uses dev-level AWS Secrets Manager
- Standard configuration
- Indicated by 🏗️ icon in Slack notifications

#### Custom Environment  
- Uses your custom .env content via ConfigMap
- Custom configuration for testing
- Indicated by 🔧 icon in Slack notifications

## Managing Feature Environments

### Manual Cleanup

To clean up a feature environment when you're done testing:

#### Option 1: Individual Cleanup (Recommended)

1. Go to **ExamX-V2-Backend-Deployment** repository
2. Navigate to **Actions** → **🧹 Cleanup Feature Environment**
3. Click **Run workflow**
4. Enter the environment name (e.g., `feat-user-authentication`)
5. Choose cleanup type:
   - **Quick Cleanup**: Just type `DELETE`
   - **Safe Cleanup**: Type the full environment name
6. Click **Run workflow**

#### Option 2: Cleanup All My Environments

1. Go to **ExamX-V2-Backend-Deployment** repository  
2. Navigate to **Actions** → **⚡ Quick Cleanup My Environments**
3. Click **Run workflow**
4. Type `CLEANUP_ALL` to confirm
5. Click **Run workflow**

This will automatically find and cleanup ALL feature environments you've created.

#### Cleanup Options

- **🧹 Individual Cleanup**: 
  - **Quick Cleanup - Just DELETE**: Fast cleanup for your own environments
  - **Safe Cleanup - Type full confirmation**: Extra safety for shared environments
- **⚡ Quick Cleanup All**: Cleanup all your environments at once (requires `CLEANUP_ALL` confirmation)

## Access URLs

Feature environments are accessible via:
```
https://{cleaned-branch-name}.examx.cloud
```

Branch names are cleaned by:
- Converting to lowercase
- Replacing special characters with hyphens
- Truncating to 20 characters max

Examples:
- `feature/user-auth` → `https://feature-user-auth.examx.cloud`
- `fix/urgent-bug-123` → `https://fix-urgent-bug-123.examx.cloud`

## Slack Notifications

The workflows send notifications to `#examxv2-backend-alerts` for:
- ✅ Successful deployments (with access URL and environment type)
- ❌ Deployment failures
- 🧹 Manual cleanups (with detailed environment info)

### Notification Icons
- 🏗️ Default environment (using dev secrets)
- 🔧 Custom environment (using custom .env)

## Best Practices

### For Developers

1. **Use descriptive branch names** - They become part of your URL
2. **Clean up early** - Use the cleanup workflow when done testing
3. **Test thoroughly** - Feature environments are perfect for stakeholder demos
4. **Use custom .env wisely** - Only when you need specific configurations

### Custom .env Guidelines

- **Default secrets**: Use for standard development/testing
- **Custom .env**: Use when testing specific configurations
- **Security**: Don't include production secrets in custom .env
- **Testing**: Perfect for feature flags, API endpoints, debug settings

### Resource Optimization

- Feature environments use minimal resources
- Multiple environments can run concurrently
- Manual cleanup prevents resource waste
- Monitor active environments regularly

## Troubleshooting

### Common Issues

1. **Branch not found**: Ensure the branch exists and is pushed to the repository
2. **Build failures**: Check Docker build logs in the CI workflow
3. **Deployment timeouts**: Check pod logs in the deployment workflow
4. **Access issues**: Verify the subdomain resolves and SSL certificate
5. **Custom .env issues**: Verify .env format and content

### Debugging Commands

Access the cluster to debug issues:

```bash
# List feature environments
kubectl get namespaces -l environment=feature

# Check specific environment
kubectl get all -n feat-{branch-name}-examxv2

# View pod logs
kubectl logs -n feat-{branch-name}-examxv2 deployment/examxv2-backend

# Check ingress
kubectl get ingress -n feat-{branch-name}-examxv2

# Check custom .env (if used)
kubectl get configmap custom-env-config -n feat-{branch-name}-examxv2 -o yaml
```

### Custom .env Troubleshooting

1. **Format validation**: Ensure .env follows `KEY=VALUE` format
2. **Base64 encoding**: Content is automatically encoded/decoded
3. **Mount path**: Custom .env is mounted at `/app/.env`
4. **Fallback**: If custom .env fails, deployment will use default secrets

### Getting Help

1. Check workflow logs in GitHub Actions
2. Review Slack notifications for error details
3. Contact the DevOps team for infrastructure issues

## Security Considerations

- Feature environments use dev-level secrets by default
- Custom .env content is stored in ConfigMaps (not recommended for production secrets)
- Each environment is isolated in its own namespace
- Manual cleanup prevents long-running exposed environments
- Access is controlled via the same authentication as other environments

## Cost Management

- Reduced resource allocations minimize costs
- Manual cleanup prevents resource waste
- Multiple cleanup mechanisms ensure no orphaned resources
- Custom environments don't incur additional secret management costs

---

## Quick Reference

| Action | Workflow | Repository | Notes |
|--------|----------|------------|-------|
| Deploy feature env | `ExamX-V2 Backend CI - Feature Branch` | ExamX-V2-Backend | Supports custom .env |
| Cleanup one environment | `🧹 Cleanup Feature Environment` | ExamX-V2-Backend-Deployment | Quick or safe cleanup |
| Cleanup all my environments | `⚡ Quick Cleanup My Environments` | ExamX-V2-Backend-Deployment | Bulk cleanup for user |

| Resource | Location | Details |
|----------|----------|---------|
| Access URL | `https://{branch-name}.examx.cloud` | Auto-generated subdomain |
| Slack alerts | `#examxv2-backend-alerts` | Real-time notifications |
| Namespace | `feat-{branch-name}-examxv2` | Isolated environment |
| Environment Types | Default or Custom | Secrets vs ConfigMap |

### Workflow Comparison

| Workflow | Purpose | When to Use | Input Required |
|----------|---------|-------------|----------------|
| `ExamX-V2 Backend CI - Feature Branch` | Deploy new feature env | Testing feature branches | Branch name, optional custom .env |
| `🧹 Cleanup Feature Environment` | Delete specific environment | Done with specific feature | Environment name + DELETE or full name |
| `⚡ Quick Cleanup My Environments` | Delete all your environments | Clean slate / end of sprint | Just "CLEANUP_ALL" |

### Example Custom .env Content
```env
# Database settings
DATABASE_URL=postgresql://user:pass@host:5432/testdb

# Feature flags
ENABLE_NEW_DASHBOARD=true
ENABLE_BETA_FEATURES=false

# API settings
EXTERNAL_API_URL=https://staging-api.example.com
API_TIMEOUT=30

# Debug settings
DEBUG=true
LOG_LEVEL=DEBUG
``` 