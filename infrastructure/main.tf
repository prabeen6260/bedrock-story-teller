provider "aws" {
  region = "us-east-2"
}

# =========================================================================
# EXISTING INFRASTRUCTURE (LAMBDA + S3 + IAM)
# =========================================================================

# 1. Reference the Existing Repo
data "aws_ecr_repository" "app_repo" {
  name = "storyteller-repo"
}

# 2. Reference the Existing Bucket
data "aws_s3_bucket" "content_bucket" {
  bucket = "bedrock-storyteller-content-us-east-2"
}

# 3. Create the Lambda Function using Docker Image
resource "aws_lambda_function" "story_generator" {
  function_name = "bedrock-story-generator"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "${data.aws_ecr_repository.app_repo.repository_url}:latest"
  
  # ARM64 architecture (matches M-series Mac build)
  architectures = ["arm64"]
  timeout       = 180  
  memory_size   = 1024 
  
  environment {
    variables = {
      BUCKET_NAME = data.aws_s3_bucket.content_bucket.id
    }
  }
}

# 4. Create a Public URL (With CORS fix for frontend)
resource "aws_lambda_function_url" "public_url" {
  function_name      = aws_lambda_function.story_generator.function_name
  authorization_type = "NONE"
  
  cors {
    allow_credentials = true
    allow_origins     = ["*"] # Allow all for now (Lock down to domain later)
    allow_methods     = ["POST"]
    allow_headers     = ["*"]
    expose_headers    = ["keep-alive", "date"]
    max_age           = 86400
  }
}

# 5. Security (Lambda Execution Role)
resource "aws_iam_role" "lambda_role" {
  name = "bedrock_story_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "bedrock_story_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Logging
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Effect = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        # Bedrock (Claude)
        Action = [
            "bedrock:InvokeModel", 
            "bedrock:InvokeModelWithResponseStream"
        ],
        Effect = "Allow",
        Resource = "*" 
      },
      {
        # SSM (Get Gemini Key)
        Action = "ssm:GetParameter",
        Effect = "Allow",
        Resource = "arn:aws:ssm:us-east-2:*:parameter/my-app/gemini-key"
      },
      {
        # S3 (Upload files)
        Action = "s3:PutObject",
        Effect = "Allow",
        Resource = "${data.aws_s3_bucket.content_bucket.arn}/*"
      }
    ]
  })
}

# =========================================================================
# NEW: GITHUB CI/CD INFRASTRUCTURE (OIDC)
# =========================================================================

# 6. Trust Provider (Allows GitHub to talk to IAM)
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # GitHub's certificate thumbprint
}

# 7. GitHub Role (The role GitHub Actions will assume)
resource "aws_iam_role" "github_actions_role" {
  name = "github-actions-deployer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:sub": "repo:prabeen6260/bedrock-story-teller:ref:refs/heads/main"
        }
      }
    }]
  })
}

# 8. GitHub Permissions (Push to ECR + Update Lambda)
resource "aws_iam_role_policy" "github_actions_policy" {
  name = "github-deploy-policy"
  role = aws_iam_role.github_actions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECRAuth"
        Action = "ecr:GetAuthorizationToken"
        Effect = "Allow"
        Resource = "*"
      },
      {
        Sid    = "AllowECRPush"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage"
        ],
        Effect = "Allow",
        Resource = data.aws_ecr_repository.app_repo.arn
      },
      {
        Sid    = "AllowLambdaUpdate"
        Action = "lambda:UpdateFunctionCode"
        Effect = "Allow"
        Resource = aws_lambda_function.story_generator.arn
      }
    ]
  })
}


# =========================================================================
# FRONTEND HOSTING (S3)
# =========================================================================

resource "aws_s3_bucket" "frontend_bucket" {
  bucket_prefix = "storyteller-frontend-" # Random unique name
  force_destroy = true
}

# 1. Enable Static Website Hosting
resource "aws_s3_bucket_website_configuration" "frontend_hosting" {
  bucket = aws_s3_bucket.frontend_bucket.id

  index_document {
    suffix = "index.html"
  }
}

# 2. Make it Public (Read-Only for everyone)
resource "aws_s3_bucket_public_access_block" "frontend_public" {
  bucket = aws_s3_bucket.frontend_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.frontend_public]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
      }
    ]
  })
}

# =========================================================================
# OUTPUTS
# =========================================================================

# Output the Website URL
output "website_url" {
  value = "http://${aws_s3_bucket_website_configuration.frontend_hosting.website_endpoint}"
}

# Output the Bucket Name (for the CI/CD pipeline to use)
output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend_bucket.id
}

output "function_url" {
  value = aws_lambda_function_url.public_url.function_url
}

output "github_role_arn" {
  value = aws_iam_role.github_actions_role.arn
}

