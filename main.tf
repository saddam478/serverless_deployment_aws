provider "aws" {
  region = "ap-south-1"
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-bucket-unique-name"
}

resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# IAM Policy for DynamoDB Access (Attach this to your IAM User/Role)
resource "aws_iam_policy" "dynamodb_policy" {
  name        = "DynamoDBFullAccess"
  description = "Policy for Terraform state locking"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:CreateTable", "dynamodb:DescribeTable", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"]
      Resource = "arn:aws:dynamodb:ap-south-1:*:table/terraform-locks"
    }]
  })
}

# Attach this policy to the user or role
resource "aws_iam_user_policy_attachment" "attach_dynamodb" {
  user       = "demo1"  # Change this to your actual IAM username
  policy_arn = aws_iam_policy.dynamodb_policy.arn
}

# ECR Repository
resource "aws_ecr_repository" "lambda_ecr_repo" {
  name                 = "lambda-ecr-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# IAM Role for Lambda
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

# Attach basic execution permissions to Lambda
resource "aws_iam_policy_attachment" "lambda_exec_attach" {
  name       = "LambdaExecPolicy"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function (Ensure the ECR Image Exists Before Running Terraform Apply)
resource "aws_lambda_function" "process_zip" {
  function_name = "process_zip_function"
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.lambda_ecr_repo.repository_url}:latest"
  role          = aws_iam_role.lambda_exec_role.arn
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
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = "GET"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.process_zip.invoke_arn
}

resource "aws_api_gateway_deployment" "example" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  depends_on = [aws_api_gateway_integration.lambda]
}

# AWS Cognito User Pool
resource "aws_cognito_user_pool" "pool" {
  name = "mypool"
}

# IAM Policy for Cognito Access (Attach to IAM User/Role)
resource "aws_iam_policy" "cognito_policy" {
  name        = "CognitoFullAccess"
  description = "Policy for Cognito User Pool"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cognito-idp:CreateUserPool", "cognito-idp:DescribeUserPool", "cognito-idp:DeleteUserPool"]
      Resource = "arn:aws:cognito-idp:ap-south-1:*:userpool/*"
    }]
  })
}

resource "aws_iam_user_policy_attachment" "attach_cognito" {
  user       = "demo1"  # Change to actual IAM user
  policy_arn = aws_iam_policy.cognito_policy.arn
}

# Outputs
output "terraform_state_bucket" {
  value = aws_s3_bucket.terraform_state.bucket
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
