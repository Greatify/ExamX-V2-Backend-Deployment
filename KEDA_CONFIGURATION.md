# KEDA Configuration Guide for ExamX-V2

**Kubernetes Event-Driven Autoscaling (KEDA)** - Advanced autoscaling for Celery workers based on Redis queue depth.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Architecture](#architecture)
- [ScaledObject Configurations](#scaledobject-configurations)
- [Configuration Details](#configuration-details)
- [Deployment](#deployment)
- [Monitoring and Verification](#monitoring-and-verification)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [Migration from HPA](#migration-from-hpa)

---

## Overview

### What is KEDA?

KEDA (Kubernetes Event-Driven Autoscaling) is a Kubernetes-based event-driven autoscaler that enables fine-grained autoscaling for workloads based on external metrics. Unlike traditional Horizontal Pod Autoscalers (HPA) that rely on CPU/memory metrics, KEDA can scale based on queue depth, event streams, and various other external metrics.

### Why KEDA for ExamX-V2?

The ExamX-V2 backend uses Celery workers to process asynchronous tasks across multiple specialized queues:

- **Default Queue**: General background tasks
- **Bulk Upload Queue**: Large data import operations
- **Question Enrichment Queue**: AI-powered question enhancement
- **Question Generator AI Queue**: AI-driven question generation

KEDA enables intelligent scaling of these workers based on actual queue depth in Redis, ensuring:

- **Cost Efficiency**: Scale down to minimum replicas when queues are empty
- **Performance**: Rapidly scale up when queue depth increases
- **Queue-Specific Scaling**: Each worker type scales independently based on its queue
- **Responsive Autoscaling**: Faster reaction time compared to traditional HPA

---

## Installation

### Prerequisites

Before installing KEDA, ensure you have:

- Kubernetes cluster (v1.23 or higher recommended)
- `kubectl` configured with cluster access
- Helm 3.x installed
- Administrative access to the cluster

### Installation Steps

#### 1. Add KEDA Helm Repository

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
```

#### 2. Install KEDA

Install KEDA version 2.17.2 in a dedicated namespace:

```bash
helm install keda kedacore/keda \
  --version 2.17.2 \
  --namespace keda \
  --create-namespace
```

#### 3. Verify Installation

Check that KEDA pods are running successfully:

```bash
kubectl get pods -n keda
```

Expected output:

```
NAME                                      READY   STATUS    RESTARTS   AGE
keda-admission-webhooks-xxxxxxxxxx-xxxxx  1/1     Running   0          2m
keda-operator-xxxxxxxxxx-xxxxx            1/1     Running   0          2m
keda-operator-metrics-apiserver-xxxxx     1/1     Running   0          2m
```

#### 4. Verify KEDA CRDs

Confirm that KEDA Custom Resource Definitions are installed:

```bash
kubectl get crd | grep keda
```

Expected CRDs:

```
scaledobjects.keda.sh
scaledjobs.keda.sh
triggerauthentications.keda.sh
clustertriggerauthentications.keda.sh
```

---

## Architecture

### KEDA Components

1. **KEDA Operator**: Core controller that manages ScaledObjects and scaling decisions
2. **Metrics Server**: Exposes external metrics to Kubernetes HPA
3. **Admission Webhooks**: Validates KEDA resource configurations

### Integration with ExamX-V2

```
┌─────────────────────────────────────────────────────────────────┐
│                         KEDA Operator                           │
│                  (Monitors Redis Queue Depth)                   │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                ┌───────────────┴───────────────┐
                │                               │
        ┌───────▼────────┐             ┌───────▼────────┐
        │ ScaledObject   │             │  Redis Broker  │
        │  Definitions   │             │   (Celery)     │
        └───────┬────────┘             └────────────────┘
                │
                │ Creates/Manages
                │
        ┌───────▼────────┐
        │  Kubernetes    │
        │      HPA       │
        └───────┬────────┘
                │
                │ Scales
                │
        ┌───────▼────────┐
        │ Celery Worker  │
        │  Deployments   │
        └────────────────┘
```

---

## ScaledObject Configurations

The ExamX-V2 deployment includes four specialized ScaledObjects for different Celery worker types, each located in `k8s/base/keda/`.

### 1. Celery Default Worker (`celery-default-scaledobject.yaml`)

Handles general background tasks from the default Celery queue.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: celery-worker-default-scaler
  labels:
    app: celery-worker-default
spec:
  scaleTargetRef:
    name: celery-worker-default
  pollingInterval: 15  
  cooldownPeriod: 60  
  minReplicaCount: 1
  maxReplicaCount: 20
  triggers:
    - type: redis
      metadata:
        addressFromEnv: REDIS_URL
        listName: "default"  
        listLength: "10"
        enableTLS: "true"
        unsafeSsl: "true"
```

**Scaling Behavior:**
- **Polling Interval**: Checks queue depth every 15 seconds
- **Cooldown Period**: Waits 60 seconds before scaling down
- **Min Replicas**: 1 (always ready to process tasks)
- **Max Replicas**: 20 (can scale up to handle high load)
- **Trigger Threshold**: Scales up when queue has more than 10 tasks

### 2. Celery Bulk Upload Worker (`celery-bulk-upload-scaledobject.yaml`)

Processes large data import and bulk upload operations.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: celery-bulk-upload-worker-scaler
  labels:
    app: celery-bulk-upload-worker
spec:
  scaleTargetRef:
    name: celery-bulk-upload-worker
  pollingInterval: 10  
  cooldownPeriod: 120  
  minReplicaCount: 1
  maxReplicaCount: 10
  triggers:
    - type: redis
      metadata:
        addressFromEnv: REDIS_URL
        listName: "bulk_upload"  
        listLength: "3"
        enableTLS: "true"
        unsafeSsl: "true"
```

**Scaling Behavior:**
- **Polling Interval**: Checks queue depth every 10 seconds (faster response)
- **Cooldown Period**: Waits 120 seconds before scaling down (bulk uploads take longer)
- **Min Replicas**: 1
- **Max Replicas**: 10 (bulk uploads are resource-intensive)
- **Trigger Threshold**: Scales up when queue has more than 3 tasks (lower threshold for heavy tasks)

### 3. Celery Enrichment Worker (`celery-enrichment-scaledobject.yaml`)

Handles AI-powered question enrichment tasks.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: celery-enrichment-worker-scaler
  labels:
    app: celery-enrichment-worker
spec:
  scaleTargetRef:
    name: celery-enrichment-worker
  pollingInterval: 15  
  cooldownPeriod: 60  
  minReplicaCount: 1
  maxReplicaCount: 15
  triggers:
    - type: redis
      metadata:
        addressFromEnv: REDIS_URL
        listName: "question_enrichment"  
        listLength: "5"
        enableTLS: "true"
        unsafeSsl: "true"
```

**Scaling Behavior:**
- **Polling Interval**: Checks queue depth every 15 seconds
- **Cooldown Period**: Waits 60 seconds before scaling down
- **Min Replicas**: 1
- **Max Replicas**: 15 (AI tasks can be parallelized)
- **Trigger Threshold**: Scales up when queue has more than 5 tasks

### 4. Celery Question Generator AI Worker (`celery-ai-generator-scaledobject.yaml`)

Processes AI-driven question generation tasks.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: celery-question-generator-ai-worker-scaler
  labels:
    app: celery-question-generator-ai-worker
spec:
  scaleTargetRef:
    name: celery-question-generator-ai-worker
  pollingInterval: 10
  cooldownPeriod: 120
  minReplicaCount: 1
  maxReplicaCount: 12
  triggers:
    - type: redis
      metadata:
        addressFromEnv: REDIS_URL
        listName: "question_generator_ai"
        listLength: "2"
        enableTLS: "true"
        unsafeSsl: "true"
```

**Scaling Behavior:**
- **Polling Interval**: Checks queue depth every 10 seconds (fast response for AI tasks)
- **Cooldown Period**: Waits 120 seconds before scaling down (AI generation takes time)
- **Min Replicas**: 1
- **Max Replicas**: 12
- **Trigger Threshold**: Scales up when queue has more than 2 tasks (AI tasks are expensive)

---

## Configuration Details

### Common Parameters Explained

#### `pollingInterval`
- **Definition**: How often KEDA checks the metric source (in seconds)
- **Range**: 1-300 seconds
- **Recommendation**: 
  - 10s for time-sensitive queues (bulk upload, AI generation)
  - 15s for standard queues (default, enrichment)

#### `cooldownPeriod`
- **Definition**: How long to wait after the last trigger before scaling down (in seconds)
- **Range**: 0-3600 seconds
- **Recommendation**:
  - 60s for fast-processing tasks (default, enrichment)
  - 120s for long-running tasks (bulk upload, AI generation)

#### `minReplicaCount`
- **Definition**: Minimum number of pods to maintain
- **Recommendation**: Set to 1 to ensure at least one worker is always available
- **Note**: Set to 0 for true scale-to-zero (but may cause cold start delays)

#### `maxReplicaCount`
- **Definition**: Maximum number of pods to scale up to
- **Calculation**: Based on:
  - Expected peak queue depth
  - Task processing time
  - Resource availability (CPU, memory)
  - Cost constraints

#### Redis Trigger Metadata

| Parameter | Description | Value for ExamX-V2 |
|-----------|-------------|---------------------|
| `addressFromEnv` | Environment variable containing Redis URL | `REDIS_URL` |
| `listName` | Name of the Redis list (Celery queue) | Queue-specific (see above) |
| `listLength` | Queue depth threshold for scaling | Varies by worker type |
| `enableTLS` | Use TLS for Redis connection | `true` |
| `unsafeSsl` | Allow self-signed certificates | `true` |

---

## Deployment

### Apply KEDA ScaledObjects

#### Deploy to Development Environment

```bash
# Navigate to deployment repository
cd ExamX-V2-Backend-Deployment

# Apply KEDA configurations (included in base kustomization)
kubectl apply -k k8s/overlays/dev
```

#### Deploy to Staging Environment

```bash
kubectl apply -k k8s/overlays/stg
```

#### Deploy to Production Environment

```bash
kubectl apply -k k8s/overlays/prod
```

### Verify ScaledObjects

```bash
# List all ScaledObjects in the namespace
kubectl get scaledobjects -n <namespace>

# Get detailed information about a specific ScaledObject
kubectl describe scaledobject celery-worker-default-scaler -n <namespace>

# Check the HPA created by KEDA
kubectl get hpa -n <namespace>
```

---

## Monitoring and Verification

### Check KEDA Scaling Status

```bash
# View ScaledObject status
kubectl get scaledobjects -n <namespace>

# Detailed status of a specific ScaledObject
kubectl describe scaledobject celery-worker-default-scaler -n <namespace>
```

### Monitor Queue Depth

```bash
# Connect to Redis to check queue depth
kubectl exec -it <redis-pod-name> -n <namespace> -- redis-cli

# Inside Redis CLI:
LLEN default
LLEN bulk_upload
LLEN question_enrichment
LLEN question_generator_ai
```

### View Worker Pod Count

```bash
# Watch pods scaling in real-time
kubectl get pods -n <namespace> -w | grep celery

# Check current replica count
kubectl get deployment -n <namespace> | grep celery
```

### KEDA Operator Logs

```bash
# View KEDA operator logs for troubleshooting
kubectl logs -n keda deployment/keda-operator --tail=100 -f

# View KEDA metrics server logs
kubectl logs -n keda deployment/keda-operator-metrics-apiserver --tail=100 -f
```

### Metrics and Dashboards

#### Prometheus Queries

If using Prometheus, monitor KEDA metrics:

```promql
# Current queue depth
keda_scaler_metrics_value{scaledObject="celery-worker-default-scaler"}

# Scaling errors
keda_scaler_errors{scaledObject="celery-worker-default-scaler"}

# Active scaling state
keda_scaledobject_paused{scaledObject="celery-worker-default-scaler"}
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. ScaledObject Not Creating HPA

**Symptoms:**
- `kubectl get scaledobjects` shows the ScaledObject, but no HPA is created
- Worker pods not scaling

**Diagnosis:**
```bash
kubectl describe scaledobject <scaledobject-name> -n <namespace>
```

**Solutions:**
- Verify KEDA operator is running: `kubectl get pods -n keda`
- Check operator logs: `kubectl logs -n keda deployment/keda-operator`
- Ensure the target deployment exists: `kubectl get deployment <deployment-name> -n <namespace>`
- Verify REDIS_URL environment variable is set in the deployment

#### 2. Workers Not Scaling Based on Queue Depth

**Symptoms:**
- Queue has many tasks, but workers don't scale up
- ScaledObject exists but scaling doesn't happen

**Diagnosis:**
```bash
# Check if KEDA can connect to Redis
kubectl logs -n keda deployment/keda-operator | grep -i redis

# Verify queue depth
kubectl exec -it <redis-pod-name> -n <namespace> -- redis-cli LLEN <queue-name>
```

**Solutions:**
- Verify `REDIS_URL` is correctly formatted: `redis://:password@host:port/db` or `rediss://` for TLS
- Check Redis connectivity from worker pods:
  ```bash
  kubectl exec -it <celery-worker-pod> -n <namespace> -- env | grep REDIS_URL
  ```
- Ensure `listName` matches the actual Celery queue name
- Adjust `listLength` threshold if it's too high

#### 3. Rapid Scaling Up and Down (Flapping)

**Symptoms:**
- Pods constantly scaling up and down
- Unstable worker count

**Solutions:**
- Increase `cooldownPeriod` to give more time before scaling down
- Increase `pollingInterval` to reduce check frequency
- Adjust `listLength` threshold to be less sensitive

#### 4. Scale-to-Zero Issues

**Symptoms:**
- Workers scale to 0 and don't come back up when tasks arrive

**Solutions:**
- Set `minReplicaCount: 1` to always keep at least one worker available
- Check KEDA operator logs for connection issues
- Verify Redis trigger is properly configured

#### 5. TLS Connection Errors

**Symptoms:**
- KEDA operator logs show TLS handshake errors
- ScaledObject status shows connection failures

**Solutions:**
- Verify `enableTLS: "true"` matches Redis configuration
- If using self-signed certificates, ensure `unsafeSsl: "true"`
- Check Redis TLS configuration and certificates

### Debug Commands

```bash
# Check KEDA CRD status
kubectl get crd scaledobjects.keda.sh -o yaml

# View all KEDA resources
kubectl get scaledobjects,triggerauthentications -A

# Get KEDA operator events
kubectl get events -n keda --sort-by='.lastTimestamp'

# Check HPA details created by KEDA
kubectl describe hpa keda-hpa-<scaledobject-name> -n <namespace>

# Force trigger evaluation (delete and recreate ScaledObject)
kubectl delete scaledobject <name> -n <namespace>
kubectl apply -f k8s/base/keda/<file>.yaml -n <namespace>
```

---

## Best Practices

### Scaling Configuration

1. **Set Appropriate Thresholds**
   - Start conservative with `listLength` thresholds
   - Monitor actual queue depths during peak load
   - Adjust thresholds based on task processing time

2. **Balance Polling and Cooldown**
   - Fast polling (10s) for time-sensitive tasks
   - Longer cooldown (120s) for expensive tasks to avoid churn
   - Monitor KEDA operator CPU usage - aggressive polling increases load

3. **Resource Limits**
   - Set realistic `maxReplicaCount` based on cluster capacity
   - Consider memory limits when scaling CPU-intensive AI workers
   - Ensure node autoscaling is configured to support max replicas

4. **Avoid Scale-to-Zero for Critical Queues**
   - Set `minReplicaCount: 1` for production environments
   - Scale-to-zero is better for dev/staging to save costs
   - Consider cold start time when deciding on min replicas

### Security Best Practices

1. **Redis Authentication**
   - Always use authentication for Redis connections
   - Store Redis credentials in Kubernetes Secrets
   - Use TLS for Redis connections in production

2. **RBAC Configuration**
   - Ensure KEDA has minimal required permissions
   - Restrict ScaledObject creation to authorized users
   - Review KEDA's service account permissions periodically

### Monitoring and Alerting

1. **Set Up Alerts**
   - Alert when workers max out (`currentReplicas == maxReplicaCount`)
   - Alert on persistent queue backlog
   - Monitor KEDA operator health and restarts

2. **Dashboard Metrics**
   - Track queue depth over time
   - Monitor scaling events frequency
   - Observe task processing latency

3. **Regular Review**
   - Review scaling patterns weekly
   - Adjust thresholds based on usage patterns
   - Optimize for cost vs. performance trade-offs

### Cost Optimization

1. **Right-Size Worker Resources**
   - Profile actual CPU/memory usage of workers
   - Adjust deployment resource requests/limits
   - More smaller workers often better than fewer large workers

2. **Environment-Specific Configuration**
   - Use lower `maxReplicaCount` in dev/staging
   - Consider scale-to-zero in non-production environments
   - Use spot instances for scaled worker pods (if supported)

3. **Queue Prioritization**
   - Route critical tasks to dedicated queues
   - Scale critical queues more aggressively
   - Use lower thresholds for high-priority tasks

---

## Migration from HPA

If you're migrating from traditional Horizontal Pod Autoscalers to KEDA:

### Before Migration

1. **Document Current HPA Configuration**
   ```bash
   kubectl get hpa -n <namespace> -o yaml > hpa-backup.yaml
   ```

2. **Record Baseline Metrics**
   - Current replica counts
   - CPU/memory utilization patterns
   - Scaling event frequency

### Migration Steps

1. **Create KEDA ScaledObjects** (already done in this deployment)

2. **Delete Existing HPAs** (if any conflict)
   ```bash
   # KEDA will create its own HPAs
   kubectl delete hpa celery-worker-default -n <namespace>
   kubectl delete hpa celery-bulk-upload-worker -n <namespace>
   kubectl delete hpa celery-enrichment-worker -n <namespace>
   kubectl delete hpa celery-question-generator-ai-worker -n <namespace>
   ```

3. **Apply KEDA ScaledObjects**
   ```bash
   kubectl apply -k k8s/overlays/<environment>
   ```

4. **Verify New Scaling Behavior**
   ```bash
   # Check KEDA-managed HPAs
   kubectl get hpa -n <namespace>
   
   # Verify they're managed by KEDA
   kubectl get hpa <hpa-name> -n <namespace> -o yaml | grep keda
   ```

### Post-Migration

1. **Monitor for 24-48 Hours**
   - Watch scaling behavior
   - Compare with previous HPA metrics
   - Adjust thresholds if needed

2. **Tune Configuration**
   - Adjust `listLength` based on actual queue patterns
   - Fine-tune polling intervals
   - Optimize cooldown periods

3. **Update Documentation**
   - Document new scaling behavior
   - Update runbooks for troubleshooting
   - Train team on KEDA-specific monitoring

---

## Additional Resources

### Official Documentation

- [KEDA Official Documentation](https://keda.sh/docs/)
- [KEDA Redis Scaler](https://keda.sh/docs/scalers/redis-lists/)
- [KEDA ScaledObject Specification](https://keda.sh/docs/concepts/scaling-deployments/)

### ExamX-V2 Specific

- [Deployment README](README.md) - Overall deployment documentation
- [Feature Environments Guide](FEATURE_ENVIRONMENTS.md) - Environment-specific configurations
- [Backend Repository](https://github.com/yourorg/ExamX-V2-Backend) - Application code

### Community Support

- [KEDA Slack](https://kubernetes.slack.com/archives/CKZJ36A5D)
- [KEDA GitHub Issues](https://github.com/kedacore/keda/issues)
- [KEDA Community Meetings](https://github.com/kedacore/keda#community)

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-10-15 | Initial KEDA configuration documentation |

---

**Note**: This configuration is optimized for ExamX-V2's Celery-based task processing architecture. Adjust parameters based on your specific workload characteristics, resource availability, and performance requirements.

