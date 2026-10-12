# service-gamma reads part of service-alpha's bucket (same account, same country: mx).
# Least privilege: one bucket, one prefix, read-only. service-alpha's other data stays out of reach, and gamma can't write anything.
iam_policy_statements = [
  {
    # List only keys under processed_reports/ (the condition restricts ListBucket).
    actions    = ["s3:ListBucket"]
    resources  = ["arn:aws:s3:::example-org-service-alpha-reports-mx"]
    conditions = [{ test = "StringLike", variable = "s3:prefix", values = ["processed_reports/*"] }]
  },
  {
    # Read objects under processed_reports/: a trailing /* on a concrete prefix is already scoped, so no justification is required.
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::example-org-service-alpha-reports-mx/processed_reports/*"]
  },
  {
    # A wildcard in the middle of the path: the folder name is a date that isn't known in advance. It must be justified (reviewed in the PR).
    actions       = ["s3:GetObject"]
    resources     = ["arn:aws:s3:::example-org-service-alpha-reports-mx/exports/*/summary.json"]
    justification = "Daily export folders are named by date (for example exports/2026-10-11/)"
  },
]
