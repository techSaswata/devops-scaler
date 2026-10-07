# ---------------------------------------------------------------------------
#  COMPUTE — EC2
# ---------------------------------------------------------------------------

# Resolve the AMI at plan time. AMI IDs are REGIONAL, so hard-coding one makes
# the configuration unusable in any other region.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.instance_type

  # Terraform infers the dependency on the subnet, SG and profile from these
  # references - no explicit depends_on needed.
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # user_data runs on first boot. The templated values prove Terraform wired
  # the pieces together.
  user_data = <<-EOT
    #!/bin/bash
    dnf install -y nginx >/dev/null 2>&1
    cat > /usr/share/nginx/html/index.html <<'HTML'
    <!doctype html><html><head><meta charset="utf-8">
    <title>Provisioned by Terraform</title></head>
    <body style="font-family:-apple-system,sans-serif;background:#0f1117;color:#e6e9f0;
                 display:grid;place-items:center;min-height:100vh;margin:0">
      <div style="border:1px solid #252a38;background:#171a23;border-radius:16px;padding:44px 52px">
        <div style="display:inline-block;background:rgba(255,153,0,.14);
                    border:1px solid rgba(255,153,0,.35);color:#ff9900;padding:6px 12px;
                    border-radius:999px;font-size:12px;font-weight:600;letter-spacing:.08em;
                    text-transform:uppercase;margin-bottom:20px">AWS EC2</div>
        <h1 style="margin:0 0 10px">Provisioned by Terraform</h1>
        <p style="color:#8b93a7;margin:0 0 22px">VPC &rarr; Subnet &rarr; Security Group &rarr; EC2 &rarr; S3</p>
        <table style="font-family:ui-monospace,Menlo,monospace;font-size:13.5px;color:#8b93a7">
          <tr><td style="padding-right:20px">region</td><td style="color:#e6e9f0">${var.aws_region}</td></tr>
          <tr><td>vpc cidr</td><td style="color:#e6e9f0">${var.vpc_cidr}</td></tr>
          <tr><td>bucket</td><td style="color:#e6e9f0">${aws_s3_bucket.assets.id}</td></tr>
        </table>
        <p style="margin-top:24px;padding-top:18px;border-top:1px solid #252a38;
                  color:#8b93a7;font-size:13px">Saswata Das &middot; 24BCS10248</p>
      </div>
    </body></html>
    HTML
    systemctl enable --now nginx
  EOT

  # Change the user_data and the instance is REPLACED, not updated in place.
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    # IMDSv2 required: session-oriented, which blocks the SSRF attacks that
    # harvested instance credentials through IMDSv1.
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = { Name = "${var.project_name}-web" }
}
