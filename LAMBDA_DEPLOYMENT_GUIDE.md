# 🚀 Lambda Functions Deployment Guide

## **Quick Start (Recommended)**

### **1. Set Environment Variables**
```bash
export OPENAI_API_KEY="sk-your-actual-openai-api-key"
export AWS_DEFAULT_REGION="ap-south-1"  # or your preferred region
```

### **2. Run the Optimized Deployment Script**
```bash
# Deploy everything in one command
./deployment/deploy_optimized_lambda.sh
```

This script will:
- ✅ Package Lambda functions (remove S3 dependencies)
- ✅ Deploy AWS infrastructure (Lambda + IAM roles only)
- ✅ Test the functions
- ✅ Show you the function names for your .env file

---

## **Manual Step-by-Step Process**

If you prefer manual control:

### **Step 1: Prepare Terraform**
```bash
cd aws_infrastructure/terraform

# Use the optimized S3-free configuration
cp main_optimized.tf main.tf

# Initialize Terraform
terraform init
```

### **Step 2: Package Lambda Functions**
```bash
# Package AI Question Generator
cd ../../lambda_functions/ai_question_generator
pip install -r requirements.txt -t .
zip -r lambda_function.zip . -x "*.pyc" "__pycache__/*"
mv lambda_function.zip ../../aws_infrastructure/terraform/ai_question_generator.zip

# Package Document Processor  
cd ../document_processor
pip install -r requirements.txt -t .
zip -r lambda_function.zip . -x "*.pyc" "__pycache__/*"
mv lambda_function.zip ../../aws_infrastructure/terraform/document_processor.zip

cd ../../aws_infrastructure/terraform
```

### **Step 3: Deploy Infrastructure**
```bash
# Plan the deployment
terraform plan \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="klockwork_api_base_url=https://klockwork.ai"

# Apply the deployment
terraform apply \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="klockwork_api_base_url=https://klockwork.ai"
```

### **Step 4: Get Function Names**
```bash
# Get the deployed function names
terraform output ai_question_generator_function_name
terraform output document_processor_function_name
```

---

## **What Gets Created**

### **AWS Resources**
- ✅ **2 Lambda Functions**:
  - `examx-v2-ai-question-generator-production`
  - `examx-v2-document-processor-production`
- ✅ **IAM Roles** for Lambda execution
- ✅ **IAM Role** for Kubernetes to invoke Lambda
- ✅ **CloudWatch Log Groups** for monitoring
- ❌ **No S3 buckets** (optimized out)

### **Lambda Functions**
1. **AI Question Generator**:
   - Runtime: Python 3.11
   - Memory: 1GB
   - Timeout: 15 minutes
   - Dependencies: OpenAI, requests
   - **No S3 dependencies**

2. **Document Processor**:
   - Runtime: Python 3.11  
   - Memory: 2GB
   - Timeout: 15 minutes
   - Dependencies: PyPDF2, requests
   - **No LlamaParse, no S3**

---

## **After Deployment**

### **1. Update Your .env File**
Add these variables to your `.env` file:
```bash
# Lambda Function Names (from terraform output)
LAMBDA_AI_QUESTION_GENERATOR=examx-v2-ai-question-generator-production
LAMBDA_DOCUMENT_PROCESSOR=examx-v2-document-processor-production

# API Configuration
EXAMX_API_BASE_URL=https://klockwork.ai

# Lambda Configuration
LAMBDA_ENABLE_AI_GENERATION=true
LAMBDA_ENABLE_DOCUMENT_PROCESSING=true
LAMBDA_FALLBACK_TO_CELERY=true
```

### **2. Deploy Kubernetes Configuration**
```bash
kubectl apply -k ExamX-V2-Backend-Deployment/k8s/overlays/prod
```

### **3. Test the Integration**
```python
# In Django shell
from ai_question_bank_generator.tasks import generate_ai_questions_optimized

# This will automatically route to Lambda
result = generate_ai_questions_optimized.delay(
    question_gen_template="Generate a test question about Python",
    database_name="your_tenant",
    task_db_id=123
)

print(f"Task ID: {result.id}")
```

---

## **Monitoring & Debugging**

### **Check Lambda Logs**
```bash
# AI Question Generator logs
aws logs tail /aws/lambda/examx-v2-ai-question-generator-production --follow

# Document Processor logs  
aws logs tail /aws/lambda/examx-v2-document-processor-production --follow
```

### **Check Lambda Functions**
```bash
# List your Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `examx-v2`)].[FunctionName,Runtime,MemorySize]' --output table
```

### **Test Lambda Directly**
```bash
# Test AI Question Generator
aws lambda invoke \
  --function-name examx-v2-ai-question-generator-production \
  --payload '{"task_id":"test-123","database_name":"test","payload":{"kwargs":{"question_gen_template":"Test question"}}}' \
  response.json

cat response.json
```

---

## **Cost Estimation**

### **Monthly Cost (Estimated)**
- **Lambda Compute**: $5-20/month (depending on usage)
- **CloudWatch Logs**: $1-3/month
- **No S3 costs**: $0 (optimized out!)
- **Total**: ~$6-25/month

### **Per Invocation Cost**
- **AI Question Generator**: ~$0.001 per invocation
- **Document Processor**: ~$0.002 per invocation

---

## **Troubleshooting**

### **Common Issues**

1. **"Function not found"**
   - Check function names with `terraform output`
   - Verify AWS region matches

2. **"Access denied"**
   - Check IAM permissions
   - Verify Kubernetes service account has correct role

3. **"Payload too large"**
   - Lambda has 6MB limit
   - Large payloads automatically fall back to Celery

4. **"OpenAI API error"**
   - Check OPENAI_API_KEY is set correctly
   - Verify API key has sufficient credits

### **Getting Help**
- Check CloudWatch logs for detailed error messages
- Use `terraform plan` to preview changes
- Test with small payloads first

---

## **Next Steps**

After successful deployment:
1. ✅ Monitor CloudWatch logs
2. ✅ Test both Lambda functions
3. ✅ Verify Celery fallback works
4. ✅ Set up alerts for failures
5. ✅ Optimize memory/timeout settings based on usage

Your S3-free, database-only Lambda architecture is now ready for production! 🎉