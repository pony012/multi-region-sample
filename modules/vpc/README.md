# vpc

Wrapper of [`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws) with the org CIDR plan: 3 tiers x 3 AZs, NAT gateways for the compute tier.

| Tier | Block (mx) | Subnets | Used by |
|---|---|---|---|
| Compute (private) | 10.0.0.0/17 | 10.0.0.0/19, 10.0.32.0/19, 10.0.64.0/19 | EKS nodes |
| Public | 10.0.128.0/20 | 10.0.128.0/22, 10.0.132.0/22, 10.0.136.0/22 | Load balancers, NAT |
| Data | 10.0.144.0/20 | 10.0.144.0/22, 10.0.148.0/22, 10.0.152.0/22 | Databases (later) |

Colombia and Brazil use the same layout with `10.32.` and `10.64.` to prevent cidr overlaps.

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name               = "platform-mx"
  cidr               = "10.0.0.0/16"
  azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
  single_nat_gateway = false # true: one NAT for the whole VPC (cheaper, non-production)
}
```