# Terraform Configuration Updates Needed

## **Required Updates in `aws_infrastructure/terraform/main.tf`**

### **1. Update EKS OIDC Issuer (CRITICAL)**

**Location:** Line 404 in `aws_infrastructure/terraform/main.tf`

**Current:**
```hcl
locals {
  oidc_issuer = "oidc.eks.ap-south-1.amazonaws.com/id/EXAMPLEGD419EXAMPLE6A90"  # Replace with actual OIDC issuer
}
```

**Update to your actual EKS OIDC issuer:**
```bash
# Get your actual OIDC issuer
aws eks describe-cluster --name YOUR_CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text
```

**Example result:** `https://oidc.eks.ap-south-1.amazonaws.com/id/ABC123DEF456GHI789JKL012`

**Update the terraform file:**
```hcl
locals {
  oidc_issuer = "oidc.eks.ap-south-1.amazonaws.com/id/ABC123DEF456GHI789JKL012"  # Your actual OIDC issuer
}
```

### **2. Optional: Update Environment Variables (if different from defaults)**

**Current defaults:**
```hcl
variable "aws_region" {
  default = "ap-south-1"
}

variable "environment" {
  default = "production"
}

variable "project_name" {
  default = "examx-v2"
}
```

**If you want different values, update when running terraform:**
```bash
terraform apply \
  -var="environment=staging" \
  -var="aws_region=us-east-1" \
  -var="project_name=examx"
```

### **3. Lambda Function Environment Variables**

**Update these sections if you want different API URLs:**

**AI Question Generator (around line 300):**
```hcl
environment {
  variables = {
    ENVIRONMENT                = var.environment
    OPENAI_SECRET_NAME        = "examx/openai-api-key"
    EXAMX_API_BASE_URL        = "https://your-actual-api-domain.com"  # UPDATE THIS
    EXAMX_API_TOKEN_SECRET    = "examx/api-tokens"
    LAMBDA_PAYLOAD_BUCKET     = aws_s3_bucket.lambda_payloads.bucket
    LAMBDA_RESULT_BUCKET      = aws_s3_bucket.lambda_results.bucket
  }
}
```

**Document Processor (around line 330):**
```hcl
environment {
  variables = {
    ENVIRONMENT                = var.environment
    LLAMAPARSE_SECRET_NAME    = "examx/llamaparse-api-key"
    EXAMX_API_BASE_URL        = "https://your-actual-api-domain.com"  # UPDATE THIS
    EXAMX_API_TOKEN_SECRET    = "examx/api-tokens"
    LAMBDA_PAYLOAD_BUCKET     = aws_s3_bucket.lambda_payloads.bucket
    LAMBDA_RESULT_BUCKET      = aws_s3_bucket.lambda_results.bucket
    DOCUMENT_STORAGE_BUCKET   = aws_s3_bucket.document_storage.bucket
  }
}
```

## **Commands to Get Required Values**

### **Get EKS OIDC Issuer:**
```bash
# Replace YOUR_CLUSTER_NAME with your actual EKS cluster name
aws eks describe-cluster --name YOUR_CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text

# Example output: https://oidc.eks.ap-south-1.amazonaws.com/id/ABC123DEF456GHI789JKL012
# Use only the part after https://: oidc.eks.ap-south-1.amazonaws.com/id/ABC123DEF456GHI789JKL012
```

### **Get Your API Domain:**
```bash
# Check your current ingress or service
kubectl get ingress -n examxv2-production
# or
kubectl get service -n examxv2-production

# Use the external URL, for example: https://api.examx.com
```

## **Deployment Steps After Updates**

1. **Update the terraform file with your values**
2. **Deploy infrastructure:**
```bash
cd aws_infrastructure/terraform
terraform init
terraform plan
terraform apply
```

3. **Get the outputs (bucket names, function names):**
```bash
terraform output
```

4. **Update your .env file** with the actual bucket names and function names from terraform output

## **Example Complete Update Process**

```bash
# 1. Get your EKS OIDC issuer
OIDC_ISSUER=$(aws eks describe-cluster --name your-cluster-name --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')
echo "Your OIDC Issuer: $OIDC_ISSUER"

# 2. Update terraform file
sed -i "s|EXAMPLEGD419EXAMPLE6A90|${OIDC_ISSUER##*/}|g" aws_infrastructure/terraform/main.tf

# 3. Deploy
cd aws_infrastructure/terraform
terraform apply -var="environment=production"

# 4. Get outputs
terraform output
```

## **Verification**

After deployment, verify:
```bash
# Check Lambda functions exist
aws lambda list-functions --query 'Functions[?contains(FunctionName, `examx-v2`)].[FunctionName]' --output table

# Check S3 buckets exist
aws s3 ls | grep examx-v2

# Check IAM role
aws iam get-role --role-name examx-v2-kubernetes-lambda-role-production
```