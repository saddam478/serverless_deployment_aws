terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket-unique-name"
    key           = "terraform.tfstate"
    region        = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt       = true
  }
}

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

# IAM Policy for S3 and DynamoDB Access
resource "aws_iam_policy" "terraform_policy" {
  name        = "TerraformStateManagement"
  description = "Policy for Terraform state management in S3 and DynamoDB"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::terraform-state-bucket-unique-name",
          "arn:aws:s3:::terraform-state-bucket-unique-name/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = [
          "dynamodb:CreateTable",
          "dynamodb:DescribeTable",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:ap-south-1:*:table/terraform-locks"
      }
    ]
  })
}

# Attach Policy to IAM User
resource "aws_iam_user_policy_attachment" "attach_terraform_policy" {
  user       = "demo1"  # Change this to your actual IAM username
  policy_arn = aws_iam_policy.terraform_policy.arn
}
