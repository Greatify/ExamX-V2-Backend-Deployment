#!/bin/bash

# Deploy Lambda Functions Script
# This script packages and deploys Lambda functions to AWS

set -e

# Configuration
ENVIRONMENT=${ENVIRONMENT:-production}
AWS_REGION=${AWS_REGION:-ap-south-1}
PROJECT_NAME="examx-v2"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed"
        exit 1
    fi
    
    # Check zip
    if ! command -v zip &> /dev/null; then
        log_error "zip command is not available"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Package Lambda function
package_lambda_function() {
    local function_name=$1
    local function_dir="lambda_functions/$function_name"
    
    log_info "Packaging $function_name..."
    
    if [ ! -d "$function_dir" ]; then
        log_error "Function directory not found: $function_dir"
        return 1
    fi
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    local package_dir="$temp_dir/$function_name"
    
    # Copy function code
    cp -r "$function_dir"/* "$package_dir/"
    
    # Install dependencies if requirements.txt exists
    if [ -f "$package_dir/requirements.txt" ]; then
        log_info "Installing dependencies for $function_name..."
        pip install -r "$package_dir/requirements.txt" -t "$package_dir/" --quiet
        
        # Remove unnecessary files to reduce package size
        find "$package_dir" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
        find "$package_dir" -type f -name "*.pyc" -delete 2>/dev/null || true
        find "$package_dir" -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
        find "$package_dir" -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
    fi
    
    # Create zip package
    local zip_file="aws_infrastructure/terraform/${function_name}.zip"
    
    cd "$package_dir"
    zip -r "../../$zip_file" . -q
    cd - > /dev/null
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log_success "Packaged $function_name -> $zip_file"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd aws_infrastructure/terraform
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    terraform plan \
        -var="environment=$ENVIRONMENT" \
        -var="aws_region=$AWS_REGION" \
        -var="project_name=$PROJECT_NAME" \
        -out=tfplan
    
    # Apply deployment
    terraform apply tfplan
    
    # Get outputs
    LAMBDA_PAYLOADS_BUCKET=$(terraform output -raw lambda_payloads_bucket)
    LAMBDA_RESULTS_BUCKET=$(terraform output -raw lambda_results_bucket)
    DOCUMENT_STORAGE_BUCKET=$(terraform output -raw document_storage_bucket)
    KUBERNETES_ROLE_ARN=$(terraform output -raw kubernetes_lambda_role_arn)
    
    cd - > /dev/null
    
    log_success "Infrastructure deployed successfully"
    log_info "Lambda Payloads Bucket: $LAMBDA_PAYLOADS_BUCKET"
    log_info "Lambda Results Bucket: $LAMBDA_RESULTS_BUCKET"
    log_info "Document Storage Bucket: $DOCUMENT_STORAGE_BUCKET"
    log_info "Kubernetes Role ARN: $KUBERNETES_ROLE_ARN"
}

# Update Kubernetes configuration
update_kubernetes_config() {
    log_info "Updating Kubernetes configuration..."
    
    # Update environment-specific configuration
    local overlay_dir="ExamX-V2-Backend-Deployment/k8s/overlays/$ENVIRONMENT"
    
    if [ ! -d "$overlay_dir" ]; then
        log_error "Environment overlay not found: $overlay_dir"
        return 1
    fi
    
    # Update lambda-config.yaml with actual bucket names
    cat > "$overlay_dir/lambda-config-patch.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: lambda-config
data:
  AWS_LAMBDA_PAYLOAD_BUCKET: "$LAMBDA_PAYLOADS_BUCKET"
  AWS_LAMBDA_RESULT_BUCKET: "$LAMBDA_RESULTS_BUCKET"
  AWS_DOCUMENT_STORAGE_BUCKET: "$DOCUMENT_STORAGE_BUCKET"
  LAMBDA_AI_QUESTION_GENERATOR: "${PROJECT_NAME}-ai-question-generator-${ENVIRONMENT}"
  LAMBDA_DOCUMENT_PROCESSOR: "${PROJECT_NAME}-document-processor-${ENVIRONMENT}"
EOF
    
    # Add patch to kustomization.yaml if not already present
    if ! grep -q "lambda-config-patch.yaml" "$overlay_dir/kustomization.yaml"; then
        echo "  - lambda-config-patch.yaml" >> "$overlay_dir/kustomization.yaml"
    fi
    
    log_success "Kubernetes configuration updated"
}

# Note: AWS Secrets Manager is no longer used - API keys are passed via .env file

# Test Lambda functions
test_lambda_functions() {
    log_info "Testing Lambda functions..."
    
    # Test AI Question Generator
    local ai_function_name="${PROJECT_NAME}-ai-question-generator-${ENVIRONMENT}"
    
    local test_payload='{
        "task_id": "test-123",
        "database_name": "test_db",
        "user_id": 1,
        "payload": {
            "task_name": "generate_ai_questions_in_celery",
            "payload": {
                "kwargs": {
                    "question_gen_template": "Generate a simple test question about mathematics.",
                    "task_db_id": 123
                }
            }
        }
    }'
    
    log_info "Testing $ai_function_name..."
    aws lambda invoke \
        --function-name "$ai_function_name" \
        --payload "$test_payload" \
        --region "$AWS_REGION" \
        /tmp/lambda_response.json
    
    if [ $? -eq 0 ]; then
        log_success "AI Question Generator test passed"
    else
        log_warning "AI Question Generator test failed - check function logs"
    fi
    
    # Test Document Processor
    local doc_function_name="${PROJECT_NAME}-document-processor-${ENVIRONMENT}"
    
    log_info "Testing $doc_function_name..."
    aws lambda invoke \
        --function-name "$doc_function_name" \
        --payload '{"task_id":"test-456","database_name":"test_db"}' \
        --region "$AWS_REGION" \
        /tmp/lambda_response2.json
    
    if [ $? -eq 0 ]; then
        log_success "Document Processor test passed"
    else
        log_warning "Document Processor test failed - check function logs"
    fi
    
    # Cleanup test files
    rm -f /tmp/lambda_response*.json
}

# Main deployment function
main() {
    log_info "Starting Lambda deployment for environment: $ENVIRONMENT"
    
    # Check prerequisites
    check_prerequisites
    
    # Package Lambda functions
    log_info "Packaging Lambda functions..."
    package_lambda_function "ai_question_generator"
    package_lambda_function "document_processor"
    
    # Deploy infrastructure
    deploy_infrastructure
    
    # Update Kubernetes configuration
    update_kubernetes_config
    
    # Test functions
    test_lambda_functions
    
    log_success "Lambda deployment completed successfully!"
    
    echo ""
    log_info "Next steps:"
    echo "1. Add API keys to your .env file (see ENV_VARIABLES_FOR_LAMBDA.md)"
    echo "2. Deploy updated Kubernetes configuration:"
    echo "   kubectl apply -k ExamX-V2-Backend-Deployment/k8s/overlays/$ENVIRONMENT"
    echo "3. Update your Django settings to use Lambda settings (already configured)"
    echo "4. Monitor Lambda function logs and metrics"
    echo ""
    log_info "Lambda functions deployed:"
    echo "- AI Question Generator: ${PROJECT_NAME}-ai-question-generator-${ENVIRONMENT}"
    echo "- Document Processor: ${PROJECT_NAME}-document-processor-${ENVIRONMENT}"
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "package")
        check_prerequisites
        package_lambda_function "ai_question_generator"
        package_lambda_function "document_processor"
        ;;
    "infrastructure")
        check_prerequisites
        deploy_infrastructure
        ;;
    "test")
        check_prerequisites
        test_lambda_functions
        ;;
    "help")
        echo "Usage: $0 [deploy|package|infrastructure|test|help]"
        echo ""
        echo "Commands:"
        echo "  deploy        - Full deployment (default)"
        echo "  package       - Package Lambda functions only"
        echo "  infrastructure - Deploy infrastructure only"
        echo "  test          - Test Lambda functions"
        echo "  help          - Show this help message"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac