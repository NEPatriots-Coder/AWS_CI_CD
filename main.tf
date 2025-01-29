# Configure the AWS Provider and required providers
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

#----------------------------------------
# S3 Bucket Configuration
#----------------------------------------

# Reference the existing S3 bucket instead of creating it
data "aws_s3_bucket" "website" {
  bucket = var.bucket_name
}

# Enable versioning for backup and recovery
resource "aws_s3_bucket_versioning" "website" {
  bucket = data.aws_s3_bucket.website.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure the bucket for static website hosting
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = data.aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Enable server-side encryption for security
resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = data.aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#----------------------------------------
# CloudFront Configuration
#----------------------------------------

# Create Origin Access Identity for CloudFront
resource "aws_cloudfront_origin_access_identity" "website" {
  comment = "OAI for ${var.bucket_name} website"
}

# Configure bucket policy to allow CloudFront access
resource "aws_s3_bucket_policy" "website" {
  bucket = data.aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PublicReadGetObject"
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.website.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${data.aws_s3_bucket.website.arn}/*"
      }
    ]
  })
}

# Set bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "website" {
  bucket = data.aws_s3_bucket.website.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Block all public access - content will be served through CloudFront
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = data.aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # Use only North America and Europe endpoints

  # Origin configuration for S3
  origin {
    domain_name = data.aws_s3_bucket.website.bucket_regional_domain_name
    origin_id   = "S3Origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.website.cloudfront_access_identity_path
    }
  }

  # Default cache behavior for most content
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600  # 1 hour
    max_ttl                = 86400 # 24 hours
    compress               = true
  }

  # Specific cache behavior for PDF files
  ordered_cache_behavior {
    path_pattern     = "assets/pdfs/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400   # 24 hours
    max_ttl                = 2592000 # 30 days
    compress               = true
  }

  # Geographic restrictions
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL/TLS certificate configuration
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # Custom error response configuration
  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/error.html"
  }
}

#----------------------------------------
# File Upload Configuration
#----------------------------------------

resource "null_resource" "upload_files" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Create website directory
      mkdir -p ./website/assets/pdfs
      
      # Copy HTML files if they exist
      [ -f ./index.html ] && cp ./index.html ./website/
      [ -f ./error.html ] && cp ./error.html ./website/
      
      # Sync to S3
      aws s3 sync ./website/ s3://${var.bucket_name} --delete
      
      if [ $? -eq 0 ]; then
        echo "Website files uploaded successfully"
        aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.website.id} --paths "/*"
      else
        echo "Failed to upload website files"
        exit 1
      fi
    EOT
  }

  depends_on = [
    data.aws_s3_bucket.website,
    aws_cloudfront_distribution.website,
    aws_s3_bucket_policy.website
  ]
}






