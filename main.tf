provider "aws" {
  region = "ap-south-1"
}

# S3 Bucket for Terraform State with Versioning
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-bucket-unique-name"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

# DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name           = "terraform-locks"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

# S3 Bucket for File Storage with Public Access
resource "aws_s3_bucket" "file_storage" {
  bucket = "file-storage-bucket-unique-name"
  acl    = "public-read"
}

# ECR Repository for Container Image Storage
resource "aws_ecr_repository" "lambda_ecr_repo" {
  name                 = "lambda-ecr-repo"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Lambda Function using ECR Image
resource "aws_lambda_function" "process_zip" {
  function_name = "process_zip_function"
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.lambda_ecr_repo.repository_url}:latest"
  role          = aws_iam_role.lambda_exec_role.arn
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.file_storage.bucket
    }
  }
}

# API Gateway for Lambda Trigger
resource "aws_api_gateway_rest_api" "api" {
  name        = "api_gateway"
  description = "API Gateway for Lambda"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "myresource"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = "GET"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.process_zip.invoke_arn
}

resource "aws_api_gateway_deployment" "example" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
  depends_on  = [aws_api_gateway_integration.lambda]
}

# AWS Cognito User Pool for SSO
resource "aws_cognito_user_pool" "pool" {
  name = "mypool"
}

# Outputs
output "terraform_state_bucket" {
  value = aws_s3_bucket.terraform_state.bucket
}

output "file_storage_bucket" {
  value = aws_s3_bucket.file_storage.bucket
}

output "ecr_repository_url" {
  value = aws_ecr_repository.lambda_ecr_repo.repository_url
}

output "lambda_function_name" {
  value = aws_lambda_function.process_zip.function_name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.example.invoke_url
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.pool.id
}
