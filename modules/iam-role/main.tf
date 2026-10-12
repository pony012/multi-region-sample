terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

variable "name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "service_account" {
  type = string
}

variable "create_pod_identity_association" {
  type        = bool
  default     = true
  description = "false only where the EKS cluster doesn't exist (LocalStack free tier)."
}

variable "policy_statements" {
  description = "Extra permissions. Wildcards need a justification (>= 20 chars)."
  type = list(object({
    actions       = list(string)
    resources     = list(string)
    justification = optional(string)
    conditions = optional(list(object({
      test     = string # StringEquals, StringLike, ...
      variable = string # s3:prefix, aws:SourceVpc, ...
      values   = list(string)
    })), [])
  }))
  default = []

  validation {
    condition = alltrue([ # Only resources with trailing /* and without justification are valid. Any other * without justification is not valid.
      for stmt in var.policy_statements : try(length(trimspace(stmt.justification)), 0) >= 20 || (
        !anytrue([for action in stmt.actions : strcontains(action, "*")]) &&
        !anytrue([for resource in stmt.resources : strcontains(resource, "*") && !can(regex("^arn:[^*]+/\\*$", resource))]) # ^arn:[^*]+/\\*$ => Resorces contains * except for trailing /*
      )
    ])
    error_message = "Least privilege: wildcard actions/resources need a `justification` of at least 20 characters."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_iam_role" "this" {
  name = var.name
  tags = var.tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "custom" {
  count = length(var.policy_statements) > 0 ? 1 : 0

  name = "custom" # We should change this in future iterations
  role = aws_iam_role.this.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [for i, stmt in var.policy_statements : merge(
      {
        Sid      = stmt.justification != null ? "JustifiedWildcard${i}" : "Stmt${i}"
        Effect   = "Allow" # We only allow, not deny (for now)
        Action   = stmt.actions
        Resource = stmt.resources
      },
      length(stmt.conditions) == 0 ? {} : {
        Condition = {
          for test in distinct([for c in stmt.conditions : c.test]) : test => {
            for condition in stmt.conditions : condition.variable => condition.values if condition.test == test
          }
        }
      }
    )]
  })
}

resource "aws_eks_pod_identity_association" "this" {
  count = var.create_pod_identity_association ? 1 : 0 # For now, for testing purposes

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.this.arn
  tags            = var.tags
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
