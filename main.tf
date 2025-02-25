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


# -------------------------------
# S3 Bucket (Public Access)
# -------------------------------
# -------------------------------
# S3 Bucket (Public Access)
# -------------------------------
resource "aws_s3_bucket" "public_bucket" {
  bucket = "my-public-bucket-unique-name456"
}

# ✅ Disable Public Access Block Policy (Allows Public Policy)
resource "aws_s3_bucket_public_access_block" "public_access_block" {
  bucket                  = aws_s3_bucket.public_bucket.id
  block_public_acls       = false
  block_public_policy     = false  # <-- Fix: Allow public policies
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# ✅ Apply Public Read-Only Policy for Objects
resource "aws_s3_bucket_policy" "public_read_policy" {
  bucket = aws_s3_bucket.public_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.public_bucket.arn}/*"
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.public_access_block]  # <-- Fix: Ensure public access block is updated first
}

# -------------------------------
# ECR Repository
# -------------------------------
#resource "aws_ecr_repository" "my_ecr_repo" {
#  name                 = "my-ecr-repo"
#  image_tag_mutability = "MUTABLE"
#}
# acheive files
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda/*.py"
  output_path = "lambda/index.zip"
}
# -------------------------------
# IAM Role for Lambda
# -------------------------------
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role"

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

# ✅ AWS Lambda Function (Python)
resource "aws_lambda_function" "yt_lambda_function" {
  function_name    = "DemoLambdaFunction"
  filename        = "lambda/index.zip"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.lambda_handler"  # Change as per your Python function
  runtime         = "python3.9"             # Adjust Python version if needed
  timeout         = 30
  source_code_hash = data.archive_file.lambda_zip_file.output_base64sha256
}

#-----------------------
# ✅ API Gateway: Create the REST API
resource "aws_api_gateway_rest_api" "yt_api" {
  name        = "yt_api"
  description = "API for Demo"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# ✅ API Gateway: Create a Resource
resource "aws_api_gateway_resource" "yt_api_resource" {
  rest_api_id = aws_api_gateway_rest_api.yt_api.id
  parent_id   = aws_api_gateway_rest_api.yt_api.root_resource_id
  path_part   = "demo-path"  # The endpoint URL will have /demo-path
}

# ✅ API Gateway: Create a Method (GET)
resource "aws_api_gateway_method" "yt_api_method" {
  rest_api_id   = aws_api_gateway_rest_api.yt_api.id
  resource_id   = aws_api_gateway_resource.yt_api_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# ✅ API Gateway: Integrate with Lambda
resource "aws_api_gateway_integration" "yt_api_integration" {
  rest_api_id             = aws_api_gateway_rest_api.yt_api.id
  resource_id             = aws_api_gateway_resource.yt_api_resource.id
  http_method             = aws_api_gateway_method.yt_api_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.yt_lambda_function.invoke_arn
}


# ✅ Deploy API Gateway
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.yt_api.id
  stage_name  = "dev"

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.yt_api_resource.id,
      aws_api_gateway_method.yt_api_method.id,
      aws_api_gateway_integration.yt_api_integration.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.yt_api_integration]
}

# ✅ Grant API Gateway permission to invoke Lambda
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.yt_lambda_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.yt_api.execution_arn}/*/*"
}

output "invoke_url" {
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}


