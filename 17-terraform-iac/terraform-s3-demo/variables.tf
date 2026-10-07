variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name, used as a prefix for resource names"
  type        = string
  default     = "devops-hw"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with hyphens."
  }
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "demo"

  validation {
    condition     = contains(["demo", "dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: demo, dev, staging, prod."
  }
}

variable "enable_versioning" {
  description = "Enable S3 object versioning"
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete a bucket that still has objects"
  type        = bool
  default     = true # demo only; NEVER true for a bucket holding real data
}
