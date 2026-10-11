Main configuration + country → AWS region, tags and deterministic names. No providers and no lookups, so `terraform plan` works before anything exists. Also refuses to plan when the Terraform workspace doesn't match the country (one state per country).

| Country | AWS region |
|---|---|
| mx | us-east-1 |
| co | us-east-2 |
| br | sa-east-1 |
