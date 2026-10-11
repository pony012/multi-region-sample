terraform {
  required_version = ">= 1.7.0"
}

variable "service" {
  type        = string
  description = "Service name (kebab-case)."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.service))
    error_message = "service must be kebab-case, 3-32 chars."
  }
}

variable "region" {
  type        = string
  description = "Country being deployed: mx | co | br (set in <country>.tfvars)."
  validation {
    condition     = contains(["mx", "co", "br"], var.region)
    error_message = "region must be mx, co or br."
  }
}

variable "regions" {
  type        = list(string)
  default     = ["mx", "co", "br"]
  description = "Countries this service is deployed to."
}

variable "workspace" {
  type        = string
  description = "terraform.workspace must equal region (one state per country)."
}

variable "team" {
  type = string
  validation {
    condition     = length(trimspace(var.team)) > 0
    error_message = "team is required."
  }
}

variable "cost_center" {
  type = string
  validation {
    condition     = length(trimspace(var.cost_center)) > 0
    error_message = "cost_center is required."
  }
}

variable "owner" {
  type    = string
  default = null
}

variable "repository" {
  type = string
}

variable "cluster" {
  type        = string
  default     = "shared"
  description = "Logical cluster; physical cluster = <cluster>-<country>."
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}

locals {
  # The only place where countries are defined (docs/conventions.md).
  countries = {
    mx = { aws_region = "us-east-1" }
    co = { aws_region = "us-east-2" }
    br = { aws_region = "sa-east-1" }
  }
  country = local.countries[var.region]
  owner   = coalesce(var.owner, var.team)

  tags = merge(var.extra_tags, {
    for k, v in {
      Service    = var.service
      Team       = var.team
      CostCenter = var.cost_center
      Owner      = local.owner
      Repository = var.repository
      Country    = var.region
      ManagedBy  = "terraform"
    } : k => replace(v, "&", "+") # AWS tag charset
  })
}

output "aws_region" {
  value = local.country.aws_region

  precondition {
    condition     = contains(var.regions, var.region)
    error_message = "Country \"${var.region}\" is not in regions = ${jsonencode(var.regions)}."
  }
  precondition {
    condition     = var.workspace == var.region
    error_message = "Workspace \"${var.workspace}\" does not match country \"${var.region}\". Run: terraform workspace select -or-create ${var.region}  (or TF_WORKSPACE=${var.region})."
  }
}

output "tags" {
  value = local.tags
}

output "owner" {
  value = local.owner
}

output "name_prefix" {
  description = "<service>-<country>"
  value       = "${var.service}-${var.region}"
}

output "cluster_name" {
  description = "<cluster>-<country>"
  value       = "${var.cluster}-${var.region}"
}

output "workload_role_name" {
  value = "${var.service}-${var.region}-workload"
}
