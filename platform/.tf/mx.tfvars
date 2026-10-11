# Mexico: us-east-1, 10.0.0.0/16, cluster shared-mx
region             = "mx"
single_nat_gateway = false # main market: one NAT gateway per AZ
node_group         = { instance_types = ["t3.large"], desired_size = 3, min_size = 2, max_size = 6 }
