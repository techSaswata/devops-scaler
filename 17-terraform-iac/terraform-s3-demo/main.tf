# A globally-unique suffix. S3 bucket names share one namespace across every
# AWS account on earth, so "my-bucket" is long gone.
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "demo" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = {
    Name = local.bucket_name
  }
}

# Versioning: keeps every version of an object, so an overwrite or delete is
# recoverable.
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Encryption at rest. SSE-S3 (AES256) is free and on by default for new buckets,
# but declaring it makes the intent explicit and auditable.
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block ALL public access. This is the single most important S3 setting - nearly
# every "S3 data breach" headline is a bucket without it.
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket                  = aws_s3_bucket.demo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule: move old versions to cheaper storage, then expire them.
resource "aws_s3_bucket_lifecycle_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  # The lifecycle rule depends on versioning being configured first. Terraform
  # infers most ordering from references; this one needs to be explicit.
  depends_on = [aws_s3_bucket_versioning.demo]

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {} # apply to every object

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# An object, to prove the bucket is usable and not just present.
resource "aws_s3_object" "readme" {
  bucket       = aws_s3_bucket.demo.id
  key          = "README.txt"
  content      = <<-EOT
    Created by Terraform.
    project:     ${var.project_name}
    environment: ${var.environment}
    region:      ${var.aws_region}
  EOT
  content_type = "text/plain"
}
