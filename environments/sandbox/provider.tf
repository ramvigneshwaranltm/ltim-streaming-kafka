terraform {
  required_version = ">= 1.0"

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

  backend "s3" {
    # Backend configuration is loaded from vars/backend.hcl
    # terraform init -backend-config=vars/backend.hcl
  }
}

provider "aws" {
  region = var.aws_region
}
