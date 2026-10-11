variable "iam_policy_statements" {
  type = list(object({
    actions       = list(string)
    resources     = list(string)
    justification = optional(string)
  }))
  default = []
}

variable "eks_pod_identity" {
  type        = bool
  default     = true
  description = "Create the Pod Identity association."
}

module "iam" {
  source = "../../../modules/iam-role"

  name                            = module.context.workload_role_name # Referenced in main.tf
  cluster_name                    = module.context.cluster_name # Referenced in main.tf
  namespace                       = var.service
  service_account                 = var.service
  create_pod_identity_association = var.eks_pod_identity
  policy_statements               = var.iam_policy_statements
}

output "workload_role" {
  value = module.iam.role_name
}
