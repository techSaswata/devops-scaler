output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "availability_zones" {
  description = "AZs the subnets are spread across"
  value       = aws_subnet.public[*].availability_zone
}

output "web_security_group_id" {
  value       = aws_security_group.web.id
  description = "ID of the web security group"
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.web.id
}

output "instance_public_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.web.public_ip
}

output "instance_private_ip" {
  description = "Private IP of the web server"
  value       = aws_instance.web.private_ip
}

output "web_url" {
  description = "URL of the provisioned web server"
  value       = "http://${aws_instance.web.public_ip}"
}

output "bucket_name" {
  description = "Name of the assets bucket"
  value       = aws_s3_bucket.assets.id
}

output "iam_role_name" {
  description = "Role the instance assumes to reach S3"
  value       = aws_iam_role.ec2.name
}
