# EKS cluster <cluster>-<country>
#
# IAM roles in this module are NOT workload roles. 
# Every IAM role has a trust policy saying WHO can assume it
# cluster role  -> eks.amazonaws.com       (the EKS control plane)
# node role     -> ec2.amazonaws.com       (the EC2 instances of the node group)
# workload role -> pods.eks.amazonaws.com  (modules/iam-role, EKS Pod Identity)
# The node role only gets what a node needs (join the cluster, pod networking pull images)
# Workloads never use it: the launch template sets the instance metadata hop limit to 1, so pods can't reach the node's credentials
# and must use their own Pod Identity role

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
  description = "<cluster>-<country>"
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private (compute) subnets for the control plane ENIs and the nodes."
}

variable "node_group" {
  type = object({
    # Prevent the usage of t family in production, specially for Spring Boot aplications that are CPU intensive in the start of the applications
    # For production we should use M family for general purpose applications, C family for compute optimized or R family for memory optimized workloads
    instance_types = optional(list(string), ["t3.medium"]) 
    desired_size   = optional(number, 2)
    min_size       = optional(number, 1)
    max_size       = optional(number, 4)
  })
  default = {}
}

variable "admin_principal_arns" {
  type        = list(string)
  default     = []
  description = "IAM roles with cluster-admin (EKS access entries), for example the platform CI role."
}

variable "tags" {
  type    = map(string)
  default = {}
}

# --- Control plane ---

resource "aws_iam_role" "cluster" {
  name = "${var.name}-cluster"
  tags = var.tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn
  tags     = var.tags

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false # private API
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_eks_access_entry" "admin" {
  for_each      = toset(var.admin_principal_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "admin" {
  for_each      = toset(var.admin_principal_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [aws_eks_access_entry.admin]
}

# --- Nodes ---

resource "aws_iam_role" "node" {
  name = "${var.name}-node"
  tags = var.tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",          # join the cluster
    "AmazonEKS_CNI_Policy",               # pod networking (VPC CNI)
    "AmazonEC2ContainerRegistryReadOnly", # pull images
  ])
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}

resource "aws_launch_template" "node" {
  name = "${var.name}-node"
  tags = var.tags

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1          # pods can't reach the node's credentials
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.node_group.instance_types
  # We should check if this AMI is the better option
  ami_type        = "AL2023_x86_64_STANDARD" # For example if we want to use graviton, we should use AL2023_ARM_64_STANDARD
  tags            = var.tags

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    desired_size = var.node_group.desired_size
    min_size     = var.node_group.min_size
    max_size     = var.node_group.max_size
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size] # owned by the autoscaler once running
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# --- Add-ons ---

resource "aws_eks_addon" "this" {
  for_each = {
    "vpc-cni"                = jsonencode({ enableNetworkPolicy = "true" }) # enforce NetworkPolicies
    "kube-proxy"             = null
    "coredns"                = null
    "eks-pod-identity-agent" = null # workload roles (modules/iam-role)
  }

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  configuration_values        = each.value
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.default]
}

output "name" {
  value = aws_eks_cluster.this.name
}

output "node_role_name" {
  value = aws_iam_role.node.name
}
