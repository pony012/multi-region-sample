variable "s3_buckets" {
  type = map(object({
    access     = optional(string, "readwrite") # read | readwrite
    versioning = optional(bool, true)
  }))
  default = {}
}

module "s3" {
  source   = "../../../modules/s3"
  for_each = var.s3_buckets

  name            = "${var.org}-${var.service}-${each.key}-${var.region}"
  access          = each.value.access
  versioning      = each.value.versioning
  grant_role_name = module.iam.role_name
}

output "buckets" {
  value = [for b in module.s3 : b.bucket_name]
}
