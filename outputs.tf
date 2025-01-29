output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.website.id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = data.aws_s3_bucket.website
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = data.aws_s3_bucket.website
}
