# iam-role

IAM role

## Constraints
For now, we're assuming that these roles will be used for EKS pods (assumed roles).
We won't allow wildcards until justified (basic justification with more than 20 characters).
A trailing `/*` on a concrete ARN or prefix (`arn:aws:s3:::bucket/processed_reports/*`) is
already scoped and needs no justification; a wildcard anywhere else
(`arn:aws:s3:::bucket/exports/*/summary.json`, `s3:Get*`, `*`) does.

# Usage
```hcl
module "iam" {
  source = "../../../modules/iam-role"

  name            = "service-alpha-mx-workload"
  cluster_name    = "shared-mx"
  namespace       = "service-alpha"
  service_account = "service-alpha"

  policy_statements = [
    # No wildcards: no justification needed.
    {
      actions   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage"]
      resources = ["arn:aws:sqs:us-east-1:123456789012:service-alpha-events"]
    },
    # A trailing "/*" scoped to one ARN is allowed without a justification.
    {
      actions   = ["s3:GetObject", "s3:PutObject"]
      resources = ["arn:aws:s3:::service-alpha-uploads/*"]
    },
    # Conditions narrow a statement: list only one prefix of another service's bucket.
    {
      actions    = ["s3:ListBucket"]
      resources  = ["arn:aws:s3:::example-org-service-alpha-reports-mx"]
      conditions = [{ test = "StringLike", variable = "s3:prefix", values = ["processed_reports/*"] }]
    },
    # Any other wildcard (in actions or resources) needs a justification of at least 20 characters.
    {
      actions       = ["cloudwatch:PutMetricData"]
      resources     = ["*"]
      justification = "PutMetricData does not support resource-level permissions"
    },
  ]

  tags = { Service = "service-alpha" }
}
```
