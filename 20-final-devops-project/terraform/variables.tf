variable "aws_region" {
  description = "Region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "taskapi"
}

variable "vpc_cidr" {
  description = "CIDR for the application VPC"
  type        = string
  default     = "10.30.0.0/16"
}
