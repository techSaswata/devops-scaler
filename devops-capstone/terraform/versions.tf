terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Every resource carries these. On a shared account this is what makes it
  # possible to prove afterwards that nothing of mine was left running.
  default_tags {
    tags = {
      Project   = "clinicflow"
      ManagedBy = "terraform"
      Owner     = var.owner_tag
    }
  }
}
