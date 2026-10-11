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
  type        = string
  description = "Bucket name: <org>-<service>-<purpose>-<country>."
}

variable "versioning" {
  type    = bool
  default = true
}

variable "grant_role_name" {
  type        = string
  default     = null
  description = "Role that gets least-privilege access (the workload role)."
}

variable "access" {
  type    = string
  default = "readwrite"
  validation {
    condition     = contains(["read", "readwrite"], var.access)
    error_message = "access must be read or readwrite."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  arn = "arn:aws:s3:::${var.name}"
  object_actions = {
    read      = ["s3:GetObject"]
    readwrite = ["s3:GetObject", "s3:PutObject"]
  }
}

resource "aws_s3_bucket" "this" {
  bucket = var.name
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_iam_role_policy" "grant" {
  count = var.grant_role_name == null ? 0 : 1

  name = "s3-${var.name}"
  role = var.grant_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "Bucket", Effect = "Allow", Action = ["s3:ListBucket"], Resource = [local.arn] },
      { Sid = "Objects", Effect = "Allow", Action = local.object_actions[var.access], Resource = ["${local.arn}/*"] },
    ]
  })
}

output "bucket_name" {
  value = aws_s3_bucket.this.id
}
