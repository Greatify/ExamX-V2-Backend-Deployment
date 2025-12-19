# Single ECR Repository for all Lambda container images
# Image tags: {lambda-name}-{environment} (e.g., fcm-dev, exam-submission-prod)

resource "aws_ecr_repository" "lambda" {
  name                 = "examx-lambda"
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  encryption_configuration {
    encryption_type = "AES256"
  }
  
  tags = {
    Name    = "examx-lambda"
    Project = "ExamX"
  }
}

# ECR Lifecycle Policy - Keep last 30 images per tag pattern
resource "aws_ecr_lifecycle_policy" "lambda" {
  repository = aws_ecr_repository.lambda.name
  
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images per Lambda per environment"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["fcm-", "exam-submission-", "enrichment-", "question-generator-ai-", "bulk-export-", "default-"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.lambda.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.lambda.name
}

# Image tag format examples:
# - fcm-dev
# - fcm-stg  
# - fcm-prod
# - exam-submission-dev
# - question-generator-ai-prod
