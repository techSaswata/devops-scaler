# ---------------------------------------------------------------------------
#  STORAGE — S3
# ---------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "assets" {
  bucket        = "${var.project_name}-assets-${random_id.suffix.hex}"
  force_destroy = true # demo only
  tags          = { Name = "${var.project_name}-assets" }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "asset" {
  bucket = aws_s3_bucket.assets.id
  key    = "config/app.json"
  content = jsonencode({
    project     = var.project_name
    environment = var.environment
    region      = var.aws_region
    vpc_cidr    = var.vpc_cidr
  })
  content_type = "application/json"
}
