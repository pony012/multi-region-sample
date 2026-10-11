Main configuration + country → AWS region, VPC CIDR, AZs, tags and deterministic names. No providers and no lookups, so `terraform plan` works before anything exists. Also refuses to plan when the Terraform workspace doesn't match the country (one state per country).

| Country | AWS region | VPC CIDR | AZs |
|---|---|---|---|
| mx | us-east-1 | 10.0.0.0/16 | us-east-1a/b/c |
| co | us-east-2 | 10.32.0.0/16 | us-east-2a/b/c |
| br | sa-east-1 | 10.64.0.0/16 | sa-east-1a/b/c |
