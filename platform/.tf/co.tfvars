# Colombia: us-east-2, 10.32.0.0/16, cluster shared-co (less capacity example)
region             = "co"
single_nat_gateway = true
node_groups = [
  { name = "default", instance_types = ["t3.medium"], desired_size = 1, min_size = 1, max_size = 2 },
]
