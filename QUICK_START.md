# 🚀 ExamX-V2 Lambda Integration - Quick Start

## **TL;DR: Get Lambda Running in 30 Minutes**

This quick start gets your hybrid Celery/Lambda architecture up and running fast. For detailed explanations, see `LAMBDA_MIGRATION_GUIDE.md`.

---

## **Prerequisites ✅**

- AWS CLI configured with appropriate permissions
- Terraform installed
- kubectl configured for your EKS cluster
- Python 3.11+ and pip

---

## **Step 1: Deploy Infrastructure (10 minutes)**

```bash
# Navigate to project directory
cd /path/to/ExamX-V2-Backend-project/backend-dev

# Deploy everything
./deployment/deploy_lambda_functions.sh deploy
```

This creates:
- ✅ Lambda functions (AI Generator, Document Processor)
- ✅ S3 buckets (payloads, results, documents)
- ✅ IAM roles and policies
- ✅ CloudWatch log groups

---

## **Step 2: Configure Secrets (5 minutes)**

```bash
# Add your actual API keys
aws secretsmanager update-secret \
    --secret-id "examx/openai-api-key" \
    --secret-string '{"OPENAI_API_KEY":"sk-your-actual-openai-key"}' \
    --region ap-south-1

aws secretsmanager update-secret \
    --secret-id "examx/llamaparse-api-key" \
    --secret-string '{"LLAMAPARSE_API_KEY":"llx_your-actual-llamaparse-key"}' \
    --region ap-south-1

aws secretsmanager update-secret \
    --secret-id "examx/api-tokens" \
    --secret-string '{"EXAMX_API_TOKEN":"your-internal-api-token"}' \
    --region ap-south-1
```

---

## **Step 3: Update Kubernetes (10 minutes)**

```bash
# Update your EKS OIDC issuer in terraform/main.tf
# Get your OIDC issuer:
aws eks describe-cluster --name your-cluster-name --query "cluster.identity.oidc.issuer" --output text

# Update the terraform file, then:
cd aws_infrastructure/terraform
terraform apply

# Deploy Kubernetes configuration
cd ../../ExamX-V2-Backend-Deployment/k8s/overlays/prod
kubectl apply -k .

# Verify deployment
kubectl get pods -n examxv2-production
```

---

## **Step 4: Test Lambda Integration (5 minutes)**

```bash
# Check if Lambda is working
kubectl logs -f deployment/examxv2-backend -n examxv2-production | grep -i lambda

# Test AI question generation (replace with your actual API endpoint)
curl -X POST "https://your-api-domain/api/ai-question-bank/generate/" \
  -H "Authorization: Bearer your-token" \
  -H "Content-Type: application/json" \
  -d '{
    "filters": {
      "course_id": ["test-course"],
      "mark": 5,
      "question_type_code": ["MCQ"]
    }
  }'
```

---

## **Step 5: Monitor Performance**

```bash
# View Lambda metrics dashboard
curl -X GET "https://your-api-domain/api/lambda-metrics/dashboard/" \
  -H "Authorization: Bearer your-token"

# Check CloudWatch logs
aws logs tail /aws/lambda/examx-v2-ai-question-generator-production --follow
```

---

## **Configuration Toggles**

Enable/disable Lambda for different environments:

```bash
# Production: Enable Lambda for AI tasks
kubectl set env deployment/examxv2-backend \
  LAMBDA_ENABLE_AI_GENERATION=true \
  LAMBDA_ENABLE_DOCUMENT_PROCESSING=true \
  -n examxv2-production

# Development: Keep using Celery
kubectl set env deployment/examxv2-backend \
  LAMBDA_ENABLE_AI_GENERATION=false \
  LAMBDA_ENABLE_DOCUMENT_PROCESSING=false \
  -n examxv2-development

# Emergency: Disable Lambda completely
kubectl set env deployment/examxv2-backend \
  LAMBDA_ENABLE_AI_GENERATION=false \
  LAMBDA_ENABLE_DOCUMENT_PROCESSING=false \
  LAMBDA_ENABLE_QUESTION_ENRICHMENT=false \
  LAMBDA_ENABLE_FILE_ANALYSIS=false \
  -n examxv2-production
```

---

## **Verify Success ✅**

Your migration is successful when:

1. **Lambda functions are deployed:**
```bash
aws lambda list-functions --query 'Functions[?contains(FunctionName, `examx-v2`)].[FunctionName]' --output table
```

2. **Tasks route to Lambda:**
```bash
kubectl logs deployment/examxv2-backend -n examxv2-production | grep "Lambda task.*invoked"
```

3. **Fallback works:**
```bash
# Disable Lambda temporarily and verify tasks still process via Celery
kubectl set env deployment/examxv2-backend LAMBDA_ENABLE_AI_GENERATION=false -n examxv2-production
```

4. **Costs are tracked:**
```bash
curl -X GET "https://your-api-domain/api/lambda-metrics/dashboard/" \
  -H "Authorization: Bearer your-token" | jq '.data.summary.total_cost_usd'
```

---

## **Rollback Plan 🔄**

If something goes wrong:

```bash
# 1. Disable Lambda routing
kubectl set env deployment/examxv2-backend \
  LAMBDA_ENABLE_AI_GENERATION=false \
  LAMBDA_ENABLE_DOCUMENT_PROCESSING=false \
  -n examxv2-production

# 2. Wait for active tasks to complete (check dashboard)

# 3. Remove Lambda configuration (if needed)
kubectl delete configmap lambda-config -n examxv2-production
kubectl delete secret examxv2-lambda-credentials -n examxv2-production
```

---

## **Common Issues & Fixes 🔧**

**Issue: "Function not found"**
```bash
# Check function names
aws lambda list-functions --query 'Functions[?contains(FunctionName, `examx`)].[FunctionName]'
```

**Issue: "Permission denied"**
```bash
# Check IAM role
kubectl describe pod -l app=examxv2-backend -n examxv2-production | grep -A5 "AWS_ROLE_ARN"
```

**Issue: "Circuit breaker open"**
```bash
# Check Lambda logs for errors
aws logs tail /aws/lambda/examx-v2-ai-question-generator-production --since 1h
```

---

## **What's Next? 🎯**

1. **Monitor performance** for 24-48 hours
2. **Adjust routing rules** based on metrics
3. **Optimize Lambda memory** settings
4. **Set up cost alerts** in AWS
5. **Plan additional task migrations**

---

## **Key Files Created**

| Purpose | File |
|---------|------|
| **Lambda Client** | `utility/aws_lambda_client.py` |
| **Hybrid Decorator** | `utility/hybrid_task_decorator.py` |
| **Settings** | `examx/lambda_settings.py` |
| **API Views** | `admin_app/views/lambda_task_views.py` |
| **Infrastructure** | `aws_infrastructure/terraform/main.tf` |
| **Deployment** | `deployment/deploy_lambda_functions.sh` |

---

**🎉 Congratulations! Your ExamX-V2 backend now intelligently routes heavy tasks to AWS Lambda while maintaining full backward compatibility with Celery.**

**Need help? Check `LAMBDA_MIGRATION_GUIDE.md` for detailed troubleshooting and advanced configuration options.**