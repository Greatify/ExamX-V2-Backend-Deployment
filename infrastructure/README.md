# ExamX Lambda Infrastructure

Terraform configuration for AWS Lambda functions with SQS integration.

## Overview

| Before | After |
|--------|-------|
| 6 Celery Workers | 1 Celery Worker + 6 Lambda Functions |
| 73 tasks on Celery | 8 heavy tasks on Celery, 65 tasks on Lambda |

## Single ECR Repository

All Lambda images are stored in a single ECR repository: `examx-lambda`

**Image Tag Format:** `{lambda-name}-{environment}`

Examples:
- `fcm-dev`
- `exam-submission-stg`
- `question-generator-ai-prod`

## Lambda Functions

| Lambda | Queue | Memory | Timeout | Image Tag |
|--------|-------|--------|---------|-----------|
| examx-{ENV}-lambda-fcm | fcm-tasks | 512 MB | 5 min | fcm-{ENV} |
| examx-{ENV}-lambda-exam-submission | exam-submissions | 1024 MB | 10 min | exam-submission-{ENV} |
| examx-{ENV}-lambda-enrichment | enrichment | 1024 MB | 15 min | enrichment-{ENV} |
| examx-{ENV}-lambda-question-generator-ai | question-generator-ai | 2048 MB | 15 min | question-generator-ai-{ENV} |
| examx-{ENV}-lambda-bulk-export | bulk-export | 2048 MB | 15 min | bulk-export-{ENV} |
| examx-{ENV}-lambda-default | default | 1024 MB | 10 min | default-{ENV} |

## Usage

### Initialize
```bash
terraform init
```

### Deploy Dev
```bash
terraform plan -var="environment=dev"
terraform apply -var="environment=dev"
```

### Deploy Prod
```bash
terraform plan -var="environment=prod"
terraform apply -var="environment=prod"
```

## Manual ECR Setup

```bash
# Create single ECR repository
aws ecr create-repository --repository-name examx-lambda

# Build and push (example for fcm-dev)
docker build -t examx-lambda:fcm-dev -f lambda/fcm/Dockerfile lambda/fcm
docker tag examx-lambda:fcm-dev 399600302704.dkr.ecr.ap-south-1.amazonaws.com/examx-lambda:fcm-dev
docker push 399600302704.dkr.ecr.ap-south-1.amazonaws.com/examx-lambda:fcm-dev
```

## Files

| File | Purpose |
|------|---------|
| main.tf | Provider, variables, locals |
| ecr.tf | Single ECR repository |
| sqs.tf | SQS queues for Lambda triggers |
| iam.tf | IAM roles and policies |
| lambda.tf | Lambda functions |
| outputs.tf | Terraform outputs |
