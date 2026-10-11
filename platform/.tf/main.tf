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

variable "cluster" {
  type = string
}
variable "node_group" {
  type    = any
  default = {}
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
  cluster     = var.cluster
}

module "vpc" {
  source = "../../modules/vpc"

  name               = "platform-${var.region}"
  cidr               = module.context.vpc_cidr
  azs                = module.context.azs
  single_nat_gateway = var.single_nat_gateway
}

module "eks" {
  source = "../../modules/eks"

  name       = module.context.cluster_name
  subnet_ids = module.vpc.private_subnet_ids
  node_group = var.node_group
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

output "cluster_name" {
  value = module.eks.name
}
