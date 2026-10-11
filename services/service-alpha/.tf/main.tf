variable "service" {
  type = string
}
variable "team" {
  type = string
}
variable "cost_center" {
  type = string
}
variable "owner" {
  type    = string
  default = null # defaults to team
}
variable "repository" {
  type = string
}
variable "regions" {
  type    = list(string)
  default = ["mx", "co", "br"]
}
variable "cluster" {
  type    = string
  default = "shared"
}
variable "org" {
  type    = string
  default = "example-org"
}
variable "region" {
  type        = string
  description = "Country: mx | co | br."
}
variable "extra_tags" {
  type    = map(string)
  default = {}
}

module "context" {
  source = "../../../modules/iam-role/context"

  service     = var.service
  region      = var.region
  regions     = var.regions
  team        = var.team
  cost_center = var.cost_center
  owner       = var.owner
  repository  = var.repository
  cluster     = var.cluster
  extra_tags  = var.extra_tags
}

output "country" {
  value = var.region
}

output "aws_region" {
  value = module.context.aws_region
}
