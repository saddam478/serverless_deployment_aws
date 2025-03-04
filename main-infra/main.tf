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
  function_name = "DemoLambdaFunction"
  timeout       = 30 # seconds
  image_uri     = "296048193302.dkr.ecr.ap-south-1.amazonaws.com/my-ecr-repo:latest"
  package_type  = "Image"
  role = aws_iam_role.lambda_role.arn
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

# ✅ Create Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "my-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = false
  }
}

# ✅ Create a User Pool Client (For App Authentication)
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "my-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  explicit_auth_flows = ["ADMIN_NO_SRP_AUTH", "USER_PASSWORD_AUTH"]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client  = true
  allowed_oauth_scopes                  = ["email", "openid", "profile"]
  callback_urls                          = ["https://my-public-bucket-unique-name456.s3.ap-south-1.amazonaws.com/logged_in.html"]  # Change this
  logout_urls                            = ["https://my-public-bucket-unique-name456.s3.ap-south-1.amazonaws.com/logged_out.html"]   # Change this
  supported_identity_providers           = ["COGNITO"]
}

# ✅ Create a Domain for Hosted UI (Optional)
resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain       = "my-unique-auth-domain-123"  # Choose a unique domain
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# ✅ Outputs
output "user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

#output "cognito_domain_url" {
#  value = "https://${aws_cognito_user_pool_domain.cognito_domain.domain}.auth.ap-south-1.amazoncognito.com"
#}


output "invoke_url" {
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}

