# Infrastructure the Task API would need in a cloud deployment:
#   - a VPC with public subnets across two AZs
#   - an S3 bucket for application artefacts and backups
#   - an ECR repository for the container image
#
# NOTE ON SCOPE: this project is VALIDATED and PLANNED but deliberately NOT
# applied. Modules 17 and 18 already created and destroyed real AWS resources
# to demonstrate the apply/destroy workflow; repeating it here would add cost
# and risk without adding anything new. See the README.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-${count.index}" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.project_name}-artifacts-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${var.project_name}-artifacts" }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE" # a tag cannot be silently repointed

  image_scanning_configuration {
    scan_on_push = true # registry-side vulnerability scanning
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.project_name}-ecr" }
}
