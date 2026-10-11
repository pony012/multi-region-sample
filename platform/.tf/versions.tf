terraform {
  required_version = "~> 1.16.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    key                  = "platform/terraform.tfstate"
    workspace_key_prefix = "countries"
  }
}

provider "aws" {
  region = module.context.aws_region
  default_tags {
    tags = module.context.tags
  }
}
