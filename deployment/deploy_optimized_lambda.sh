#!/bin/bash

# ExamX-V2 Optimized Lambda Deployment Script (S3-Free)
# This script deploys the optimized Lambda functions without S3 dependencies

set -e

# Configuration
PROJECT_NAME="examx-v2"
ENVIRONMENT="production"
AWS_REGION="ap-south-1"
KLOCKWORK_API_URL="https://klockwork.ai"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it."
        exit 1
    fi
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not found. Please install it."
        exit 1
    fi
    
    if ! command -v zip &> /dev/null; then
        log_error "zip command not found. Please install it."
        exit 1
    fi
    
    log_success "All dependencies found"
}

# Package Lambda functions
package_lambda_functions() {
    log_info "Packaging Lambda functions..."
    
    # AI Question Generator
    cd lambda_functions/ai_question_generator
    if [ -f lambda_function.zip ]; then
        rm lambda_function.zip
    fi
    pip install -r requirements.txt -t .
    zip -r lambda_function.zip . -x "*.pyc" "__pycache__/*"
    mv lambda_function.zip ../../aws_infrastructure/terraform/ai_question_generator.zip
    log_success "AI Question Generator packaged"
    cd ../..
    
    # Document Processor
    cd lambda_functions/document_processor
    if [ -f lambda_function.zip ]; then
        rm lambda_function.zip
    fi
    pip install -r requirements.txt -t .
    zip -r lambda_function.zip . -x "*.pyc" "__pycache__/*"
    mv lambda_function.zip ../../aws_infrastructure/terraform/document_processor.zip
    log_success "Document Processor packaged"
    cd ../..
}

# Deploy infrastructure
deploy_infrastructure() {
    log_info "Deploying AWS infrastructure..."
    
    cd aws_infrastructure/terraform
    
    # Use optimized terraform file
    if [ -f main_optimized.tf ]; then
        if [ -f main.tf ]; then
            mv main.tf main_old.tf
            log_warning "Backed up old main.tf to main_old.tf"
        fi
        mv main_optimized.tf main.tf
        log_info "Using optimized Terraform configuration"
    fi
    
    # Initialize Terraform
    terraform init
    
    # Validate configuration
    terraform validate
    
    # Plan deployment
    log_info "Planning Terraform deployment..."
    terraform plan \
        -var="project_name=${PROJECT_NAME}" \
        -var="environment=${ENVIRONMENT}" \
        -var="aws_region=${AWS_REGION}" \
        -var="klockwork_api_base_url=${KLOCKWORK_API_URL}" \
        -var="openai_api_key=${OPENAI_API_KEY:-placeholder}"
    
    # Apply configuration
    log_info "Applying Terraform configuration..."
    terraform apply -auto-approve \
        -var="project_name=${PROJECT_NAME}" \
        -var="environment=${ENVIRONMENT}" \
        -var="aws_region=${AWS_REGION}" \
        -var="klockwork_api_base_url=${KLOCKWORK_API_URL}" \
        -var="openai_api_key=${OPENAI_API_KEY:-placeholder}"
    
    cd ../..
    log_success "Infrastructure deployed successfully"
}

# Get deployment outputs
get_outputs() {
    log_info "Getting deployment outputs..."
    
    cd aws_infrastructure/terraform
    
    AI_FUNCTION_NAME=$(terraform output -raw ai_question_generator_function_name)
    DOC_FUNCTION_NAME=$(terraform output -raw document_processor_function_name)
    LAMBDA_ROLE_ARN=$(terraform output -raw kubernetes_lambda_role_arn)
    
    cd ../..
    
    echo ""
    log_success "Deployment completed successfully!"
    echo ""
    log_info "Lambda Functions:"
    echo "  - AI Question Generator: ${AI_FUNCTION_NAME}"
    echo "  - Document Processor: ${DOC_FUNCTION_NAME}"
    echo ""
    log_info "IAM Role for Kubernetes: ${LAMBDA_ROLE_ARN}"
}

# Test Lambda functions
test_functions() {
    log_info "Testing Lambda functions..."
    
    cd aws_infrastructure/terraform
    AI_FUNCTION_NAME=$(terraform output -raw ai_question_generator_function_name)
    
    # Test AI Question Generator with minimal payload
    TEST_PAYLOAD='{
        "task_id": "test-123",
        "database_name": "test_db",
        "user_id": "test_user",
        "payload": {
            "kwargs": {
                "question_gen_template": "Generate a simple test question about mathematics"
            }
        }
    }'
    
    log_info "Testing AI Question Generator..."
    aws lambda invoke \
        --function-name "${AI_FUNCTION_NAME}" \
        --payload "${TEST_PAYLOAD}" \
        --region "${AWS_REGION}" \
        test_response.json
    
    if [ $? -eq 0 ]; then
        log_success "AI Question Generator test passed"
        cat test_response.json
        rm test_response.json
    else
        log_warning "AI Question Generator test failed (may need actual API keys)"
    fi
    
    cd ../..
}

# Main deployment function
main() {
    log_info "Starting ExamX-V2 Optimized Lambda deployment..."
    log_info "Project: ${PROJECT_NAME}, Environment: ${ENVIRONMENT}"
    log_info "Using S3-free, database-only architecture"
    
    # Check for required environment variables
    if [ -z "${OPENAI_API_KEY}" ]; then
        log_warning "OPENAI_API_KEY not set. Using placeholder (update after deployment)"
    fi
    
    check_dependencies
    package_lambda_functions
    deploy_infrastructure
    get_outputs
    test_functions
    
    echo ""
    log_success "🚀 Optimized Lambda deployment completed!"
    echo ""
    log_info "Next steps:"
    echo "1. Update your .env file with the function names above"
    echo "2. Set OPENAI_API_KEY in Terraform variables if not already set"
    echo "3. Deploy Kubernetes configuration:"
    echo "   kubectl apply -k ExamX-V2-Backend-Deployment/k8s/overlays/${ENVIRONMENT}"
    echo "4. Test the hybrid task routing in your Django application"
    echo ""
    log_info "📊 Benefits of optimized architecture:"
    echo "  ✅ No S3 storage costs"
    echo "  ✅ Faster direct result return"
    echo "  ✅ Simplified AWS permissions"
    echo "  ✅ Database-only result storage"
    echo ""
}

# Run main function
main "$@"