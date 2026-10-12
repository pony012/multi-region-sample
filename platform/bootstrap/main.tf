# The Terraform state bucket. Local state.

terraform {
  required_version = "~> 1.16.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

module "state" {
  source = "../../modules/state-backend"
  # If we have more than one account, it's important to have different account/region name
  # for each state
  bucket_name = "tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

output "bucket_name" {
  value = module.state.bucket_name
}
