# VPC for one country (wrapper of terraform-aws-modules/vpc).
# Same /16 layout everywhere; only the second octet changes
# (mx 10.0, co 10.32, br 10.64)
# I've decided this because if we want to have a centralized VPN to access something inside our VPCs,
# we need to prevent overlaps (or for future implementations).
# Compute x.x.0.0/17    compute (private, NAT)  3 x /19   EKS nodes
# Public  x.x.128.0/20  public                  3 x /22   load balancers, NAT
# Data    x.x.144.0/20  data                    3 x /22   RDS, ElastiCache (later)
# the rest is reserved for future usage

terraform {
  required_version = ">= 1.7.0"
}

variable "name" {
  type        = string
  description = "platform-<country>"
}

variable "cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "true: one NAT for the VPC (cheaper); false: one NAT per AZ (production)."
}

variable "tags" {
  type    = map(string)
  default = {}
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.cidr
  azs  = var.azs

  # Compute x.x.0.0/17    compute (private, NAT)  3 x /19   EKS nodes
  # Public  x.x.128.0/20  public                  3 x /22   load balancers, NAT
  # Data    x.x.144.0/20  data                    3 x /22   RDS, ElastiCache (later)
  # 10.0.0.0   ─┬─ /19 private AZ-a ┐
  # 10.0.32.0   ├─ /19 private AZ-b │ Compute /17 (0–127)
  # 10.0.64.0   ├─ /19 private AZ-c │
  # 10.0.96.0   ├─ /19 (free)       ┘
  # 10.0.128.0  ├─ /22 public a/b/c + 1 free (140) ── Public /20 (128–143)
  # 10.0.144.0  ├─ /22 data a/b/c + 1 free (156)   ── Data /20 (144–159)
  # 10.0.160.0  └─ free (160–255): about 24k addresses for later
  # https://developer.hashicorp.com/terraform/language/functions/cidrsubnet
  private_subnets  = [for i in range(3) : cidrsubnet(var.cidr, 3, i)]      # 10.0.0.0/19, 10.0.32.0/19, 10.0.64.0/19
  public_subnets   = [for i in range(3) : cidrsubnet(var.cidr, 6, 32 + i)] # 10.0.128.0/22, 10.0.132.0/22, 10.0.136.0/22
  database_subnets = [for i in range(3) : cidrsubnet(var.cidr, 6, 36 + i)] # 10.0.144.0/22, 10.0.148.0/22, 10.0.152.0/22

  private_subnet_tags  = { Tier = "Compute", "kubernetes.io/role/internal-elb" = "1" } # Tag / annotation for k8s
  public_subnet_tags   = { Tier = "Public", "kubernetes.io/role/elb" = "1" }           # Tag / annotation for k8s
  database_subnet_tags = { Tier = "Data" }

  create_database_subnet_group = false
  enable_nat_gateway           = true
  single_nat_gateway           = var.single_nat_gateway
  one_nat_gateway_per_az       = !var.single_nat_gateway
  enable_dns_hostnames         = true
  enable_dns_support           = true

  tags = var.tags
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}
