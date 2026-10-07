# ---------------------------------------------------------------------------
#  SECURITY GROUPS — the stateful, instance-level firewall
# ---------------------------------------------------------------------------

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound HTTP; allow all outbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the allowed CIDR"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
  }

  # NOTE: no SSH rule. Port 22 open to 0.0.0.0/0 is the most commonly abused
  # misconfiguration in AWS. Access is via SSM Session Manager instead, which
  # needs no inbound port at all.

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-web-sg" }
}

# The app tier accepts traffic ONLY from the web security group - referenced by
# ID, not by CIDR. The rule keeps working as instances come and go, which is the
# same reasoning as a Kubernetes label selector.
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Allow 8080 from the web tier only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from the web tier"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-app-sg" }
}

# ---------------------------------------------------------------------------
#  IAM — an instance ROLE, so the EC2 instance reaches S3 with NO access key
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Least privilege: only this bucket, only read actions.
data "aws_iam_policy_document" "s3_read" {
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.assets.arn,        # bucket-level, for ListBucket
      "${aws_s3_bucket.assets.arn}/*", # object-level, for GetObject
    ]
  }
}

resource "aws_iam_role_policy" "s3_read" {
  name   = "${var.project_name}-s3-read"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.s3_read.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}
