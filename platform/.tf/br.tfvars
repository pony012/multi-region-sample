# Brazil: sa-east-1, 10.64.0.0/16, cluster shared-br
region             = "br"
single_nat_gateway = true
node_groups = [
  { name = "default", instance_types = ["t3.medium"], desired_size = 2, min_size = 1, max_size = 4 },
]
