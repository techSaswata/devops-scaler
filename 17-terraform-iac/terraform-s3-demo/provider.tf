# Provider configuration and version pinning.
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"   # allow 5.x patches, never a 6.x breaking change
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Credentials are NOT configured here. Terraform reads them from the standard
  # chain: environment variables, then ~/.aws/credentials, then the instance
  # role. Putting keys in a .tf file commits them to git.

  default_tags {
    # Applied to every resource this provider creates, so nothing is untagged
    # and everything is attributable.
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "24BCS10248"
    }
  }
}
