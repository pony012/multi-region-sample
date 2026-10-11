terraform {
  required_version = "~> 1.16.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Remote state (bucket and region come from ../../../backend.hcl).
  # We could move this to another location
  backend "s3" {
    key = "services/service-alpha/terraform.tfstate"
  }
}

provider "aws" { # We could move this to another location
  region = "us-east-1" # Mexico: the only country for now
  default_tags {
    tags = {
      Service    = var.service
      Team       = var.team
      CostCenter = var.cost_center
      ManagedBy  = "terraform"
    }
  }
}
