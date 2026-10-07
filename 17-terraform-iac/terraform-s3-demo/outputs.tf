output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.demo.id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.demo.arn
}

output "bucket_region" {
  description = "Region the bucket lives in"
  value       = aws_s3_bucket.demo.region
}

output "versioning_status" {
  description = "Whether object versioning is enabled"
  value       = aws_s3_bucket_versioning.demo.versioning_configuration[0].status
}

output "public_access_blocked" {
  description = "Confirms all four public-access blocks are on"
  value = alltrue([
    aws_s3_bucket_public_access_block.demo.block_public_acls,
    aws_s3_bucket_public_access_block.demo.block_public_policy,
    aws_s3_bucket_public_access_block.demo.ignore_public_acls,
    aws_s3_bucket_public_access_block.demo.restrict_public_buckets,
  ])
}
