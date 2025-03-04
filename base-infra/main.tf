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

# ✅ Create ECR Repository
resource "aws_ecr_repository" "my_ecr_repo" {
  name                 = "my-ecr-repo"
  image_tag_mutability = "MUTABLE"
}

# ✅ Output ECR Repository URL
output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = aws_ecr_repository.my_ecr_repo.repository_url
}

output "terraform_state_bucket" {
  description = "Terraform State S3 Bucket Name"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "public_storage_bucket" {
  description = "Public File Storage S3 Bucket Name"
  value       = aws_s3_bucket.public_bucket.bucket
}
