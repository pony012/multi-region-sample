variable "service" {
  type = string
}
variable "team" {
  type = string
}
variable "cost_center" {
  type = string
}
variable "repository" {
  type = string
}
variable "regions" {
  type = list(string)
}
variable "region" {
  type        = string
  description = "Country: set in <country>.tfvars."
}
variable "single_nat_gateway" {
  type    = bool
  default = false
}

module "context" {
  source = "../../modules/context"

  service     = var.service
  region      = var.region
  regions     = var.regions
  workspace   = terraform.workspace
  team        = var.team
  cost_center = var.cost_center
  repository  = var.repository
}

module "vpc" {
  source = "../../modules/vpc"

  name               = "platform-${var.region}"
  cidr               = module.context.vpc_cidr
  azs                = module.context.azs
  single_nat_gateway = var.single_nat_gateway
}

output "country" {
  value = var.region
}

output "aws_region" {
  value = module.context.aws_region
}

output "vpc_cidr" {
  value = module.context.vpc_cidr
}
