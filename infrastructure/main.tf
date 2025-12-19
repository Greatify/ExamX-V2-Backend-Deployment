# ExamX Lambda Infrastructure
# Terraform configuration for Lambda functions with SQS

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket = "examx-terraform-state"
    key    = "lambda/terraform.tfstate"
    region = "ap-south-1"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "ExamX"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Variables
variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
  default     = "399600302704"
}

variable "vpc_subnet_ids" {
  description = "VPC Subnet IDs for Lambda"
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "VPC Security Group IDs for Lambda"
  type        = list(string)
  default     = []
}

# Local variables
locals {
  prefix = "examx-${var.environment}"
  
  lambdas = {
    fcm = {
      timeout     = 300   # 5 minutes
      memory_size = 512
      queue       = "fcm-tasks"
      description = "FCM notifications and device commands"
    }
    exam-submission = {
      timeout     = 600   # 10 minutes
      memory_size = 1024
      queue       = "exam-submissions"
      description = "Exam submission processing"
    }
    enrichment = {
      timeout     = 900   # 15 minutes
      memory_size = 1024
      queue       = "enrichment"
      description = "Question enrichment and indexing"
    }
    question-generator-ai = {
      timeout     = 900   # 15 minutes
      memory_size = 2048
      queue       = "question-generator-ai"
      description = "AI question generation"
    }
    bulk-export = {
      timeout     = 900   # 15 minutes
      memory_size = 2048
      queue       = "bulk-export"
      description = "Bulk data export"
    }
    default = {
      timeout     = 600   # 10 minutes
      memory_size = 1024
      queue       = "default"
      description = "Default tasks (email, JAMF, etc.)"
    }
  }
}
