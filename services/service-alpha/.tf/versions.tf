terraform {
  required_version = "~> 1.16.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Remote state (bucket and region come from ../../../backend.hcl).
  backend "s3" {
    key = "services/service-alpha/terraform.tfstate"
  }
}

provider "aws" {
  region = module.context.aws_region # from the country (var.region)
  default_tags {
    tags = module.context.tags
  }
}
