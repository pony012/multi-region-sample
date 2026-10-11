# eks

Private EKS cluster `<cluster>-<country>` (for example `shared-mx`) with a managed node group in the private (compute) subnets and only the add-ons workloads need: VPC CNI (with NetworkPolicy enforcement), kube-proxy, CoreDNS and the EKS Pod Identity agent.

## IAM roles: nodes vs workloads

Every IAM role has a **trust policy** (`assume_role_policy`) that says who can assume it. There's no role without one: what changes is the principal.

| Role | Trusted principal | Permissions | Created by |
|---|---|---|---|
| `<cluster>-<country>-cluster` | `eks.amazonaws.com` | `AmazonEKSClusterPolicy` | this module |
| `<cluster>-<country>-node` | `ec2.amazonaws.com` (the node group's instances, through an instance profile EKS creates) | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` | this module |
| `<service>-<country>-workload` | `pods.eks.amazonaws.com` (EKS Pod Identity) | the service's own (S3, ...) | `modules/iam-role` |

Applications must **not** use the node role: every pod on the node would share it. The launch template enforces this: IMDSv2 only, with hop limit 1, so containers can't read the node's credentials and use their Pod Identity role instead.

## Usage

```hcl
module "eks" {
  source = "../../modules/eks"

  name       = "shared-mx"
  subnet_ids = module.vpc.private_subnet_ids # compute tier from modules/vpc

  node_group = {
    instance_types = ["t3.large"]
    desired_size   = 3
    min_size       = 2
    max_size       = 6
  }

  # Optional: extra cluster admins (EKS access entries), e.g. the platform CI role.
  admin_principal_arns = ["arn:aws:iam::123456789012:role/platform-ci"]
}
```