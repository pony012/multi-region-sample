terraform {
  required_version = "~> 1.16.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    key                  = "services/service-alpha/terraform.tfstate"
    workspace_key_prefix = "countries"
  }
}

provider "aws" {
  region = module.context.aws_region # from the country in <country>.tfvars
  default_tags {
    tags = module.context.tags
  }
}
