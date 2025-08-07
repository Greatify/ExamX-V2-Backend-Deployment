# Environment Variables to Add to Your .env File

Add these variables to your existing `.env` file that's mounted via `examxv2-secrets.yaml`:

## **AWS Configuration**
```bash
# AWS Region
AWS_DEFAULT_REGION=ap-south-1

# AWS Credentials (if not using IAM roles)
# AWS_ACCESS_KEY_ID=your-access-key-id
# AWS_SECRET_ACCESS_KEY=your-secret-access-key

# S3 Buckets (will be created by Terraform)
AWS_LAMBDA_PAYLOAD_BUCKET=examx-v2-lambda-payloads-production
AWS_LAMBDA_RESULT_BUCKET=examx-v2-lambda-results-production
AWS_DOCUMENT_STORAGE_BUCKET=examx-v2-document-storage-production
```

## **Lambda Function Names**
```bash
# Lambda Function Names (will be created by Terraform)
LAMBDA_AI_QUESTION_GENERATOR=examx-v2-ai-question-generator-production
LAMBDA_DOCUMENT_PROCESSOR=examx-v2-document-processor-production
LAMBDA_QUESTION_ENRICHMENT=examx-v2-question-enrichment-production
LAMBDA_FILE_ANALYZER=examx-v2-file-analyzer-production
```

## **API Keys (Required)**
```bash
# OpenAI API Key for AI Question Generation
OPENAI_API_KEY=sk-your-actual-openai-api-key-here

# LlamaParse API Key for Document Processing
LLAMAPARSE_API_KEY=llx_your-actual-llamaparse-api-key-here

# Internal API Token for Lambda -> Django communication
EXAMX_API_TOKEN=your-internal-api-token-here
EXAMX_API_BASE_URL=https://your-api-domain.com
```

## **Lambda Configuration (Optional - has defaults)**
```bash
# Enable/Disable Lambda for specific task types
LAMBDA_ENABLE_AI_GENERATION=true
LAMBDA_ENABLE_DOCUMENT_PROCESSING=true
LAMBDA_ENABLE_QUESTION_ENRICHMENT=false
LAMBDA_ENABLE_FILE_ANALYSIS=true

# Performance Settings
LAMBDA_TIMEOUT_SECONDS=900
LAMBDA_MEMORY_MB=1024
LAMBDA_MAX_PAYLOAD_SIZE=6291456

# Cost Control
LAMBDA_MAX_DAILY_COST_USD=100.0
LAMBDA_COST_ALERT_THRESHOLD_USD=80.0

# Circuit Breaker
LAMBDA_CIRCUIT_BREAKER_ENABLED=true
LAMBDA_CIRCUIT_BREAKER_FAILURE_THRESHOLD=5
LAMBDA_CIRCUIT_BREAKER_TIMEOUT_SECONDS=300

# Fallback Settings
LAMBDA_FALLBACK_TO_CELERY=true
LAMBDA_FALLBACK_TIMEOUT_SECONDS=60
```

## **Environment-Specific Values**

### **Development Environment**
```bash
AWS_LAMBDA_PAYLOAD_BUCKET=examx-v2-lambda-payloads-development
AWS_LAMBDA_RESULT_BUCKET=examx-v2-lambda-results-development
LAMBDA_AI_QUESTION_GENERATOR=examx-v2-ai-question-generator-development
LAMBDA_DOCUMENT_PROCESSOR=examx-v2-document-processor-development
LAMBDA_ENABLE_AI_GENERATION=false  # Use Celery in dev
LAMBDA_ENABLE_DOCUMENT_PROCESSING=false  # Use Celery in dev
LAMBDA_MAX_DAILY_COST_USD=10.0
```

### **Staging Environment**
```bash
AWS_LAMBDA_PAYLOAD_BUCKET=examx-v2-lambda-payloads-staging
AWS_LAMBDA_RESULT_BUCKET=examx-v2-lambda-results-staging
LAMBDA_AI_QUESTION_GENERATOR=examx-v2-ai-question-generator-staging
LAMBDA_DOCUMENT_PROCESSOR=examx-v2-document-processor-staging
LAMBDA_MAX_DAILY_COST_USD=50.0
```

### **Production Environment**
```bash
AWS_LAMBDA_PAYLOAD_BUCKET=examx-v2-lambda-payloads-production
AWS_LAMBDA_RESULT_BUCKET=examx-v2-lambda-results-production
LAMBDA_AI_QUESTION_GENERATOR=examx-v2-ai-question-generator-production
LAMBDA_DOCUMENT_PROCESSOR=examx-v2-document-processor-production
LAMBDA_MAX_DAILY_COST_USD=100.0
```