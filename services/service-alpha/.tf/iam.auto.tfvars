iam_policy_statements = [
  {
    actions       = ["cloudwatch:PutMetricData"]
    resources     = ["*"]
    justification = "PutMetricData does not support resource-level permissions"
  },
]
