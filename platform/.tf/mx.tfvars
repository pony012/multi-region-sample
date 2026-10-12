# Mexico: us-east-1, 10.0.0.0/16, cluster shared-mx
region             = "mx"
single_nat_gateway = false # one NAT gateway per AZ
node_groups = [
  { name = "default", instance_types = ["t3.large"], desired_size = 3, min_size = 2, max_size = 6 },
  {
    # For example for batch jobs: tainted, scales from 0.
    name           = "batch"
    instance_types = ["r7i.large"]
    desired_size   = 1
    min_size       = 0
    max_size       = 4
    taints         = [{ key = "platform.example.org/node-group", value = "batch", effect = "NO_SCHEDULE" }]
  },
]
