# ExamX-V2 AWS Lambda Infrastructure (S3-Free Optimized Version)
# This Terraform configuration sets up AWS Lambda functions without S3 dependencies

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "examx-v2"
}

variable "openai_api_key" {
  description = "OpenAI API Key"
  type        = string
  default     = ""
  sensitive   = true
}

variable "klockwork_api_base_url" {
  description = "Klockwork API Base URL"
  type        = string
  default     = "https://klockwork.ai"
}

# IAM Role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-execution-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "ExamX Lambda Execution Role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Policy for Lambda execution (minimal permissions)
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "${var.project_name}-lambda-execution-policy-${var.environment}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# IAM Role for Kubernetes Service Account (IRSA)
resource "aws_iam_role" "kubernetes_lambda_role" {
  name = "${var.project_name}-kubernetes-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_issuer}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer}:sub" = "system:serviceaccount:examxv2-${var.environment}:examxv2-${var.environment}-sa"
            "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "ExamX Kubernetes Lambda Role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Policy for Kubernetes to invoke Lambda
resource "aws_iam_role_policy" "kubernetes_lambda_policy" {
  name = "${var.project_name}-kubernetes-lambda-policy-${var.environment}"
  role = aws_iam_role.kubernetes_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeLambda"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.ai_question_generator.arn,
          aws_lambda_function.document_processor.arn
        ]
      }
    ]
  })
}

# AI Question Generator Lambda Function
resource "aws_lambda_function" "ai_question_generator" {
  filename         = "ai_question_generator.zip"
  function_name    = "${var.project_name}-ai-question-generator-${var.environment}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = filebase64sha256("ai_question_generator.zip")
  runtime         = "python3.11"
  timeout         = 900  # 15 minutes
  memory_size     = 1024

  environment {
    variables = {
      ENVIRONMENT                = var.environment
      EXAMX_API_BASE_URL        = var.klockwork_api_base_url
      OPENAI_API_KEY            = var.openai_api_key
    }
  }

  tags = {
    Name        = "ExamX AI Question Generator"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Document Processor Lambda Function
resource "aws_lambda_function" "document_processor" {
  filename         = "document_processor.zip"
  function_name    = "${var.project_name}-document-processor-${var.environment}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = filebase64sha256("document_processor.zip")
  runtime         = "python3.11"
  timeout         = 900  # 15 minutes
  memory_size     = 2048  # More memory for document processing

  environment {
    variables = {
      ENVIRONMENT                = var.environment
      EXAMX_API_BASE_URL        = var.klockwork_api_base_url
    }
  }

  tags = {
    Name        = "ExamX Document Processor"
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "ai_question_generator_logs" {
  name              = "/aws/lambda/${aws_lambda_function.ai_question_generator.function_name}"
  retention_in_days = 14

  tags = {
    Name        = "ExamX AI Question Generator Logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "document_processor_logs" {
  name              = "/aws/lambda/${aws_lambda_function.document_processor.function_name}"
  retention_in_days = 14

  tags = {
    Name        = "ExamX Document Processor Logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Data sources
data "aws_caller_identity" "current" {}

# Update this with your actual EKS cluster OIDC issuer
locals {
  oidc_issuer = "oidc.eks.ap-south-1.amazonaws.com/id/EXAMPLEGD419EXAMPLE6A90"  # Replace with actual OIDC issuer
}

# Outputs
output "kubernetes_lambda_role_arn" {
  description = "ARN of the IAM role for Kubernetes Lambda invocation"
  value       = aws_iam_role.kubernetes_lambda_role.arn
}

output "ai_question_generator_function_name" {
  description = "Name of the AI Question Generator Lambda function"
  value       = aws_lambda_function.ai_question_generator.function_name
}

output "document_processor_function_name" {
  description = "Name of the Document Processor Lambda function"
  value       = aws_lambda_function.document_processor.function_name
}

output "ai_question_generator_arn" {
  description = "ARN of the AI Question Generator Lambda function"
  value       = aws_lambda_function.ai_question_generator.arn
}

output "document_processor_arn" {
  description = "ARN of the Document Processor Lambda function"
  value       = aws_lambda_function.document_processor.arn
}