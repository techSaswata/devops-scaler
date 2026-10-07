variable "aws_region" {
  description = "Region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
  default     = "devops-hw-infra"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the public subnets, one per AZ"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the private subnets, one per AZ"
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type (t3.micro and t2.micro are free-tier eligible)"
  type        = string
  default     = "t3.micro"
}

variable "allowed_http_cidr" {
  description = "CIDR permitted to reach the web server on port 80"
  type        = string
  default     = "0.0.0.0/0"
}
