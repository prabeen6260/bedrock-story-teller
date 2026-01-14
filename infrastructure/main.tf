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

# 2. Reference the Existing Content Bucket (For images/stories)
data "aws_s3_bucket" "content_bucket" {
  bucket = "bedrock-storyteller-content-us-east-2"
}

# 3. Create the Lambda Function using Docker Image
resource "aws_lambda_function" "story_generator" {
  function_name = "bedrock-story-generator"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "${data.aws_ecr_repository.app_repo.repository_url}:latest"
  
  # Architecture set to x86_64 for GitHub Actions compatibility
  architectures = ["x86_64"]
  timeout       = 180  
  memory_size   = 1024 
  
  environment {
    variables = {
      BUCKET_NAME = data.aws_s3_bucket.content_bucket.id
    }
  }
}

# 4. Create a Public URL (With CORS fix)
resource "aws_lambda_function_url" "public_url" {
  function_name      = aws_lambda_function.story_generator.function_name
  authorization_type = "NONE"
  
  cors {
    allow_credentials = true
    allow_origins     = ["*"] 
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
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Effect = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
            "bedrock:InvokeModel", 
            "bedrock:InvokeModelWithResponseStream"
        ],
        Effect = "Allow",
        Resource = "*" 
      },
      {
        Action = "ssm:GetParameter",
        Effect = "Allow",
        Resource = "arn:aws:ssm:us-east-2:*:parameter/my-app/gemini-key"
      },
      {
        Action = "s3:PutObject",
        Effect = "Allow",
        Resource = "${data.aws_s3_bucket.content_bucket.arn}/*"
      }
    ]
  })
}

# =========================================================================
# FRONTEND INFRASTRUCTURE (THE MISSING PART!)
# =========================================================================

resource "aws_s3_bucket" "frontend_bucket" {
  bucket_prefix = "storyteller-frontend-" 
  force_destroy = true
}

# Enable Static Website Hosting
resource "aws_s3_bucket_website_configuration" "frontend_hosting" {
  bucket = aws_s3_bucket.frontend_bucket.id

  index_document {
    suffix = "index.html"
  }
}

# Make it Public (Read-Only) - Required for S3 Website + CloudFront
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
# GITHUB CI/CD INFRASTRUCTURE (OIDC)
# =========================================================================

# 6. Trust Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] 
}

# 7. GitHub Role
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

# 8. GitHub Permissions
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
      },
      {
        Sid    = "AllowS3Deploy"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ],
        Effect = "Allow",
        Resource = [
          aws_s3_bucket.frontend_bucket.arn,      
          "${aws_s3_bucket.frontend_bucket.arn}/*" 
        ]
      }
    ]
  })
}

# =========================================================================
# DOMAIN & HTTPS CONFIGURATION
# =========================================================================

variable "root_domain" {
  default = "lambda-lambs.com"
}

variable "subdomain" {
  default = "story-teller" 
}

# 1. Reference the Hosted Zone
data "aws_route53_zone" "main" {
  name = var.root_domain
}

# 2. HTTPS Certificate
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

resource "aws_acm_certificate" "site_cert" {
  provider          = aws.us_east_1
  domain_name       = "${var.subdomain}.${var.root_domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# 3. CloudFront Distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id   = "S3-Frontend"
    
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["${var.subdomain}.${var.root_domain}"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Frontend"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.site_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access" {
  comment = "Access Identity for Lambda Lambs"
}

# 4. DNS Records
resource "aws_route53_record" "subdomain_record" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.subdomain}.${var.root_domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.site_cert.domain_validation_options : dvo.domain_name => dvo
  }

  allow_overwrite = true
  name            = each.value.resource_record_name
  records         = [each.value.resource_record_value]
  ttl             = 60
  type            = each.value.resource_record_type
  zone_id         = data.aws_route53_zone.main.zone_id
}

output "live_url" {
  value = "https://${var.subdomain}.${var.root_domain}"
}

output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend_bucket.id
}

output "function_url" {
  value = aws_lambda_function_url.public_url.function_url
}

output "github_role_arn" {
  value = aws_iam_role.github_actions_role.arn
}