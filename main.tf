terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket-unique-name123"
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
provider "aws" {
  region = "ap-south-1"
}

# ✅ S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-bucket-unique-name123"
}

resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ✅ DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ✅ IAM Policy for DynamoDB Access
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

# ✅ Attach the IAM Policy to Your User
resource "aws_iam_user_policy_attachment" "attach_dynamodb" {
  user       = "demo1"  # Change this to your IAM username
  policy_arn = aws_iam_policy.dynamodb_policy.arn
}

terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket-unique-name"
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-south-1"
}

# -------------------------------
# S3 Bucket (Public Access)
# -------------------------------
resource "aws_s3_bucket" "public_bucket" {
  bucket = "my-public-bucket-unique-name"
}

resource "aws_s3_bucket_acl" "public_access" {
  bucket = aws_s3_bucket.public_bucket.id
  acl    = "public-read"
}

# -------------------------------
# ECR Repository
# -------------------------------
resource "aws_ecr_repository" "my_ecr_repo" {
  name                 = "my-ecr-repo"
  image_tag_mutability = "MUTABLE"
}

# -------------------------------
# IAM Role for Lambda
# -------------------------------
resource "aws_iam_role" "lambda_role" {
  name = "lambda-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy_attachment" "lambda_basic_exec" {
  name       = "lambda-basic-exec"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy_attachment" "lambda_ecr_access" {
  name       = "lambda-ecr-access"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# -------------------------------
# Lambda Function (ECR Image)
# -------------------------------
resource "aws_lambda_function" "ecr_lambda" {
  function_name = "my-ecr-lambda"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"

  image_uri = "${aws_ecr_repository.my_ecr_repo.repository_url}:latest"

  timeout     = 10
  memory_size = 128

  depends_on = [
    aws_iam_policy_attachment.lambda_basic_exec,
    aws_iam_policy_attachment.lambda_ecr_access
  ]
}

# -------------------------------
# API Gateway (Trigger Lambda)
# -------------------------------
resource "aws_apigatewayv2_api" "http_api" {
  name          = "my-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.ecr_lambda.invoke_arn
}

resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /lambda"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecr_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}



