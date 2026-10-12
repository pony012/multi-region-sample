# multi-region-sample
Multi-region deployment sample of K8s and AWS infrastructure.

# Goal
Create a mechanism to create AWS infrastructure for a new service without the need of manual work or tribal knowledge.
There will be two main users:
1. Platform Engineers
2. Software Engineers

The idea is that Platform Engineers provide the tooling and work framework to the Software Engineers, such as:
1. Running EKS cluster with one or more NodeGroups
2. Terraform Modules for each needed AWS Service (for this example, IAM and S3, but the idea is that developers could have RDS, Elasticache, MSK Clusers and Topics, and so on).

And the Software Engineers should be able to have templates with minimal needed configuration like:
```
├── .tf/
│   ├── main.tf
│   ├── iam.tf # Reference to the Platform Provided Module
│   ├── s3.tf # Reference to the Platform Provided Module
│   ├── mx.tfvars
│   ├── co.tfvars
│   └── br.tfvars
└── .k8s/
    ├── base/
    └── overlays/<country>/
```

And the Software Developers should have the ability to select on which cluster / nodegroup they want to deploy its service, and what IAM permissions they should provide to its service. The modules should have the needed harness to prevent non-least-privilege-access (such as prevention of wildcard (`*`) usage).

# Architecture
For this example, we will work with at least three folders in a monorepo (this repo):
```
├── modules
│   ├── eks/
│   ├── iam/
│   └── s3/
├── platform
│   └── .tf/
│       ├── main.tf
│       ├── br.tfvars
│       ├── co.tfvars
│       └── mx.tfvars
├── services/
│   ├── service-alpha
│   ├── service-beta
│   └── ..
```

Its important to say that the name of the assets should be deterministic, we must use EKS Pod Identity and not the IAM roles of the nodes itself, and we should be able to test this with Localstack. Also, we will separate the cluster itself (eks) for its "virtual" components such as Namespaces, we will have kubernetes service configurations as manifests in each service repository.

The CI/CD pipeline should be able to apply the Software Engineering teams services' configurations to each country like `terraform plan-var-file=<region>.tfvars` (we will run these commands in our local).

# Terraform
I recommend to use `tfenv` (`brew install tfenv`), but you can install standalone terraform with
```
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```
Latest minor version is `1.16`.

# Requirements and test

## Localstack (v4.14, before March 23, 2026 changes in licensing)
### Installation
I've added the docker image to a docker-compose.yml file, you just need to do `docker compose up -d` and then check if it's running with `curl -sf http://localhost:4566/_localstack/health`.
### Test
I've added a `scripts/localstack.test` with the sample environment variables to test, so you can test the localstack installation with:
```
source scripts/localstack.env
aws sts get-caller-identity --query Account --output text --no-cli-pager
```

If you got an error of `InvalidClientTokenId` is that you're using aws cli v1.x, and you have to manually pass the `--endpoint-url=http://localhost:4566` to your commands. I recommend you to install the AWS CLI v2.

## Basic state management with localstack

I've prepared the basic state management that we will use in `platform/bootstrap`, so you can run:
```
cd platform/bootstrap
terraform init && terraform apply
cd ../..
```
If you got an error like `Error: timeout while waiting for plugin to start`, it's because the Docker Machine for localstack was too small. Give it more resources.
I will work with podman, in my case I used
````
podman machine stop
podman machine init --rootful podman-machine-rootful
podman machine stop podman-machine-rootful
podman machine set --memory 6144 podman-machine-rootful
podman machine start podman-machine-rootful
````

# Steps

## Step 0
Run
```
source scripts/localstack.env
cd platform/bootstrap
terraform init && terraform apply
```
Check the plan, write `yes` and press `Enter`, you should see
```
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

bucket_name = "tfstate-000000000000-us-east-1"
```

## Step 1

In this step we only run `terraform plan`: nothing is applied. The goal is to check every plan, and see if it is coherent with its country before anything reaches an account.

Every Terraform root (`services/<service>/.tf` and `platform/.tf`) is planned once per country, **in the workspace with the country's name** (one state per country, available countries are mx, co and br):

```
terraform workspace select -or-create <country>
terraform plan -var-file=<country>.tfvars
```

### What to expect per country

Keep this table at hand: every value you read in a plan must belong to the country's row.

| Country | Workspace / tfvars | AWS region | AZs | VPC CIDR | EKS cluster | Conventional names |
|---|---|---|---|---|---|---|
| Mexico | `mx` / `mx.tfvars` | `us-east-1` | `us-east-1a/b/c` | `10.0.0.0/16` | `shared-mx` | `-mx` / `-mx-...` |
| Colombia | `co` / `co.tfvars` | `us-east-2` | `us-east-2a/b/c` | `10.32.0.0/16` | `shared-co` | `-co` / `-co-...` |
| Brazil | `br` / `br.tfvars` | `sa-east-1` | `sa-east-1a/b/c` | `10.64.0.0/16` | `shared-br` | `-br` / `-br-...` |

And in every plan, check:

1. `Changes to Outputs` (at the end)
2. `region = "..."` in each resource.
3. `"Country" = "..."` in `tags_all`.
4. Names (`name`, `bucket`, `cluster_name`, `role`) carry the country name.
5. `Plan: N to add, M to change, 0 to destroy`: nothing should be destroyed or replaced.
6. IAM policies: any `*` in `Action` or `Resource` (except for trailing `/*` after a specific ARN) only appears in a statement with `Sid = "JustifiedWildcard*"`.

> The `Plan:` counts below are for an empty state (if you only had run the Step 0). If you already applied something in that workspace, you'll see fewer additions or `No changes`.

### 1.1 Load the LocalStack variables

From the repository root:
```
source scripts/localstack.test
```

### 1.2 Workload: service-alpha

Initialize the root with the state bucket from Step 0 (only once per root):
```
cd services/service-alpha/.tf
terraform init -reconfigure -backend-config=../../../backend.hcl
```

Plan Mexico:
```
terraform workspace select -or-create mx
terraform plan -var-file=mx.tfvars
```

<details>
<summary>Output</summary>

```
Terraform should perform the following actions:

  # module.iam.aws_eks_pod_identity_association.this[0] will be created
  + resource "aws_eks_pod_identity_association" "this" {
      + cluster_name         = "shared-mx"
      + namespace            = "service-alpha"
      + region               = "us-east-1"
      + service_account      = "service-alpha"
      + tags_all             = {
          + "Compliance" = "ARCO"
          + "CostCenter" = "Engineering"
          + "Country"    = "mx"
          + "ManagedBy"  = "terraform"
          + "Owner"      = "Guild-Ledger"
          + "Repository" = "github.com/some-example-org/service-alpha"
          + "Service"    = "service-alpha"
          + "Team"       = "example-team"
        }
        ...
    }

  # module.iam.aws_iam_role.this will be created
  + resource "aws_iam_role" "this" {
      + assume_role_policy    = jsonencode(
            {
              + Statement = [
                  + {
                      + Action    = [
                          + "sts:AssumeRole",
                          + "sts:TagSession",
                        ]
                      + Effect    = "Allow"
                      + Principal = {
                          + Service = "pods.eks.amazonaws.com"
                        }
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + name                  = "service-alpha-mx-workload"
      + tags_all              = {
          + "Country"    = "mx"
          ...
        }
        ...
    }

  # module.iam.aws_iam_role_policy.custom[0] will be created
  + resource "aws_iam_role_policy" "custom" {
      + policy      = jsonencode(
            {
              + Statement = [
                  + {
                      + Action   = [
                          + "cloudwatch:PutMetricData",
                        ]
                      + Effect   = "Allow"
                      + Resource = [
                          + "*",
                        ]
                      + Sid      = "JustifiedWildcard0"
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + role        = "service-alpha-mx-workload"
    }

Plan: 3 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + aws_region    = "us-east-1"
  + country       = "mx"
  + workload_role = "service-alpha-mx-workload"
```
</details>

Now Colombia and Brazil, in the same directory:
```
terraform workspace select -or-create co
terraform plan -var-file=co.tfvars

terraform workspace select -or-create br
terraform plan -var-file=br.tfvars
```
Same resources, with the values of their row:

| Workspace | `Plan:` | `aws_region` / `region` | Role | `cluster_name` |
|---|---|---|---|---|
| `co` | 3 to add, 0 to destroy | `us-east-2` | `service-alpha-co-workload` | `shared-co` |
| `br` | 3 to add, 0 to destroy | `sa-east-1` | `service-alpha-br-workload` | `shared-br` |

### 1.3 Workload: service-beta

```
cd ../../service-beta/.tf
terraform init -reconfigure -backend-config=../../../backend.hcl

terraform workspace select -or-create mx
terraform plan -var-file=mx.tfvars
```

<details>
<summary>Output (summary)</summary>

```
  # module.iam.aws_eks_pod_identity_association.this[0] will be created
  # module.iam.aws_iam_role.this will be created
  # module.s3["reports"].aws_iam_role_policy.grant[0] will be created
  # module.s3["reports"].aws_s3_bucket.this will be created
  # module.s3["reports"].aws_s3_bucket_public_access_block.this will be created
  # module.s3["reports"].aws_s3_bucket_server_side_encryption_configuration.this will be created
  # module.s3["reports"].aws_s3_bucket_versioning.this will be created

  # module.s3["reports"].aws_iam_role_policy.grant[0] will be created
  + resource "aws_iam_role_policy" "grant" {
      + name        = "s3-example-org-service-beta-reports-mx"
      + policy      = jsonencode(
            {
              + Statement = [
                  + {
                      + Action   = [
                          + "s3:ListBucket",
                        ]
                      + Effect   = "Allow"
                      + Resource = [
                          + "arn:aws:s3:::example-org-service-beta-reports-mx",
                        ]
                      + Sid      = "Bucket"
                    },
                  + {
                      + Action   = [
                          + "s3:GetObject",
                        ]
                      + Effect   = "Allow"
                      + Resource = [
                          + "arn:aws:s3:::example-org-service-beta-reports-mx/*",
                        ]
                      + Sid      = "Objects"
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + role        = "service-beta-mx-workload"
    }

  # module.s3["reports"].aws_s3_bucket.this will be created
  + resource "aws_s3_bucket" "this" {
      + bucket                      = "example-org-service-beta-reports-mx"
      + region                      = "us-east-1"
      + tags_all                    = {
          + "Country"    = "mx"
          ...
        }
        ...
    }

Plan: 7 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + aws_region    = "us-east-1"
  + buckets       = [
      + (known after apply),
    ]
  + country       = "mx"
  + workload_role = "service-beta-mx-workload"
```
</details>

The bucket is `example-org-service-beta-reports-mx`, every S3 resource has `region = "us-east-1"`, and the grant is read-only (`access = "read"`): `s3:ListBucket` on the bucket and `s3:GetObject` on `.../*`, no wildcard actions.

```
terraform workspace select -or-create co
terraform plan -var-file=co.tfvars

terraform workspace select -or-create br
terraform plan -var-file=br.tfvars
```

| Workspace | `Plan:` | `aws_region` / `region` | Role | Bucket | `cluster_name` |
|---|---|---|---|---|---|
| `co` | 2 to add, 0 to destroy | `us-east-2` | `service-beta-co-workload` | none (`buckets = []`) | `shared-co` |
| `br` | 7 to add, 0 to destroy | `sa-east-1` | `service-beta-br-workload` | `example-org-service-beta-reports-br` | `shared-br` |

Colombia has no bucket because `co.tfvars` sets `s3_buckets = {}`: the country tfvars can turn resources on or off per country.

### 1.4 Wrong workspace for the country

We should be able to prevent, for example planning Colombia's config into Mexico's state.
Still in `services/service-beta/.tf`:
```
terraform workspace select mx
terraform plan -var-file=co.tfvars
```

<details>
<summary>Output</summary>

```
Error: Module output value precondition failed

  on ../../../modules/context/main.tf line 102, in output "aws_region":
 102:     condition     = var.workspace == var.region
    ├────────────────
    │ var.region is "co"
    │ var.workspace is "mx"

Workspace "mx" does not match country "co". Run: terraform workspace select -or-create co  (or TF_WORKSPACE=co).
```
</details>

The plan fails before showing any resource, so a wrong combination can't even be reviewed (or applied) by mistake.

### 1.5 Platform: VPC and EKS cluster for Mexico

For `mx.tfvars`, we will create two node groups, and for co and br, we will create only the default one.
```
cd ../../../platform/.tf
terraform init -reconfigure -backend-config=../../backend.hcl

terraform workspace select -or-create mx
terraform plan -var-file=mx.tfvars
```

<details>
<summary>Output (summary)</summary>

```
  # module.eks.aws_eks_addon.this["coredns"] will be created
  # module.eks.aws_eks_addon.this["eks-pod-identity-agent"] will be created
  # module.eks.aws_eks_addon.this["kube-proxy"] will be created
  # module.eks.aws_eks_addon.this["vpc-cni"] will be created
  # module.eks.aws_eks_cluster.this will be created
  # module.eks.aws_eks_node_group.default will be created
  # module.eks.aws_iam_role.cluster will be created
  # module.eks.aws_iam_role.node will be created
  # module.eks.aws_iam_role_policy_attachment.cluster will be created
  # module.eks.aws_iam_role_policy_attachment.node["AmazonEC2ContainerRegistryReadOnly"] will be created
  # module.eks.aws_iam_role_policy_attachment.node["AmazonEKSWorkerNodePolicy"] will be created
  # module.eks.aws_iam_role_policy_attachment.node["AmazonEKS_CNI_Policy"] will be created
  # module.eks.aws_launch_template.node will be created
  # module.vpc.module.vpc.aws_vpc.this[0] will be created
  # module.vpc.module.vpc.aws_subnet.private[0..2] will be created
  # module.vpc.module.vpc.aws_subnet.public[0..2] will be created
  # module.vpc.module.vpc.aws_subnet.database[0..2] will be created
  # module.vpc.module.vpc.aws_nat_gateway.this[0..2] will be created
  # module.vpc.module.vpc.aws_eip.nat[0..2] will be created
  # module.vpc.module.vpc.aws_internet_gateway.this[0] will be created
  # ... route tables, routes, associations, default ACL / route table / security group

Plan: 51 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + aws_region   = "us-east-1"
  + cluster_name = "shared-mx"
  + country      = "mx"
  + node_groups  = {
      + batch   = {
          + node_selector = {
              + "platform.example.org/node-group" = "batch"
            }
          + taints        = [
              + {
                  + effect = "NO_SCHEDULE"
                  + key    = "platform.example.org/node-group"
                  + value  = "batch"
                },
            ]
        }
      + default = {
          + node_selector = {
              + "platform.example.org/node-group" = "default"
            }
          + taints        = []
        }
    }
  + vpc_cidr     = "10.0.0.0/16"
```
</details>

| Resource | Expected value in the plan |
|---|---|
| `aws_vpc.this[0]` | `cidr_block = "10.0.0.0/16"` |
| `aws_subnet.private[0..2]` (compute) | `10.0.0.0/19`, `10.0.32.0/19`, `10.0.64.0/19` in `us-east-1a`, `b`, `c` |
| `aws_subnet.public[0..2]` | `10.0.128.0/22`, `10.0.132.0/22`, `10.0.136.0/22` in `us-east-1a`, `b`, `c` |
| `aws_subnet.database[0..2]` | `10.0.144.0/22`, `10.0.148.0/22`, `10.0.152.0/22` in `us-east-1a`, `b`, `c` |
| `aws_nat_gateway.this[0..2]` | 3 (one per AZ: `single_nat_gateway = false` in `mx.tfvars`) |
| `aws_eks_cluster.this` | `name = "shared-mx"`, `endpoint_public_access = false` |
| `aws_eks_node_groups` | `{ node_group_name = "default"..., node_group_name = "batch" }` |
| `aws_iam_role.cluster` / `.node` | `shared-mx-cluster` / `shared-mx-node` |
| `aws_launch_template.node` | `http_tokens = "required"`, `http_put_response_hop_limit = 1` |

### 1.6 Kubernetes manifests: render each overlay

Each service keeps its Kubernetes manifests in `.k8s/`: a `base/` shared by every country and one `overlays/<country>/` per country where it runs (today the overlay only sets the `COUNTRY` env var). Like `terraform plan`, `kubectl kustomize` only renders the final YAML of an overlay: it doesn't need a cluster and applies nothing.

From the repository root:
```
kubectl kustomize services/<service>/.k8s/overlays/<country>
```

For example, Colombia for `service-alpha`:
```
kubectl kustomize services/service-alpha/.k8s/overlays/co
```
Repeat it for every `services/*/.k8s/overlays/*` folder. In each rendered output, we could check:

1. Everything is in the service's namespace (`namespace: <service>`), including the `Namespace` itself, its `ServiceAccount` and the two `NetworkPolicy` (`default-deny-ingress` + `allow-clients`).
2. `serviceAccountName: <service>`: it's the ServiceAccount bound to the `<service>-<country>-workload` role by the Pod Identity association planned in the service's `.tf` (`namespace` and `service_account` in the plan).
3. `COUNTRY` has the overlay's country (`value: co`).
4. The node group: with no `nodeSelector` nor `tolerations`, the pods run on the `default` node group (`service-alpha` and `service-beta`).

#### service-gamma: opt-in to the batch node group

`service-gamma` is a batch worker that only runs in Mexico, so it has a single overlay:
```
kubectl kustomize services/service-gamma/.k8s/overlays/mx
```

<details>
<summary>Output (Deployment)</summary>

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-gamma
  namespace: service-gamma
spec:
  replicas: 2
  ...
  template:
    spec:
      containers:
      - env:
        - name: COUNTRY
          value: mx
        ...
      nodeSelector:
        platform.example.org/node-group: batch
      ...
      serviceAccountName: service-gamma
      tolerations:
      - effect: NoSchedule
        key: platform.example.org/node-group
        operator: Equal
        value: batch
```
</details>

These two blocks are the service's side of the `batch` node group planned in 1.5 (`node_groups` output of the platform plan):

| Platform (`platform/.tf/mx.tfvars`, `modules/eks`) | service-gamma (`.k8s/base/deployment.yaml`) | Effect |
|---|---|---|
| Label `platform.example.org/node-group=batch` on every `batch` node | `nodeSelector: { platform.example.org/node-group: batch }` | gamma's pods can only run on `batch` nodes |
| Taint `platform.example.org/node-group=batch:NoSchedule` (`NO_SCHEDULE` in Terraform) | `tolerations: [{ key: platform.example.org/node-group, operator: Equal, value: batch, effect: NoSchedule }]` | gamma's pods are allowed on the tainted nodes. Poods without it (alpha, beta) are kept out |

Both are needed: the toleration alone would let gamma run on `default` or `batch`, and the `nodeSelector` alone would leave the pods `Pending` (the only matching nodes have a taint they don't tolerate). Together, `batch` is exclusive for the services that opt in, and `default` stays for everybody else. `modules/eks` enforces the platform side: an untainted `default` group is required, and any other group must have a taint.

**Important**:
- The `batch` group only exists in `platform/.tf/mx.tfvars`. That's why `service-gamma` only has `overlays/mx` (and `regions = ["mx"]` in its Terraform): an overlay for `co` or `br` would leave its pods `Pending`, since those clusters have no `batch` nodes. There's nothing to render for them:
  ```
  $ kubectl kustomize services/service-gamma/.k8s/overlays/co
    Error: evalsymlink failure on 'services/service-gamma/.k8s/overlays/co' : lstat /Users/alan/repo/clara-private/multi-region-sample/services/service-gamma/.k8s/overlays/co: no such file or directory
  ```
- `batch` has `min_size = 0`: if it has no running nodes, gamma's pods stay `Pending` until the group scales up, which needs an autoscaler (Cluster Autoscaler or Karpenter).

### 1.7 Workload: service-gamma (least-privilege access to service-alpha's bucket)

`service-gamma` has no bucket of its own: it reads a subfolder of the bucket owned by `service-alpha` (`example-org-service-alpha-reports-mx`). Instead of reusing alpha's role, or giving `s3:*` on the whole bucket, its own role (`service-gamma-mx-workload`) gets only what it needs, declared in `services/service-gamma/.tf/iam.auto.tfvars`

```
cd services/service-gamma/.tf
terraform init -reconfigure -backend-config=../../../backend.hcl

terraform workspace select -or-create mx
terraform plan -var-file=mx.tfvars
```

<details>
<summary>Output (summary)</summary>

```
  # module.iam.aws_eks_pod_identity_association.this[0] will be created
      + cluster_name         = "shared-mx"
      + namespace            = "service-gamma"
      + region               = "us-east-1"
      + service_account      = "service-gamma"
  # module.iam.aws_iam_role.this will be created
      + name                  = "service-gamma-mx-workload"

  # module.iam.aws_iam_role_policy.custom[0] will be created
  + resource "aws_iam_role_policy" "custom" {
      + name        = "custom"
      + policy      = jsonencode(
            {
              + Statement = [
                  + {
                      + Action    = [
                          + "s3:ListBucket",
                        ]
                      + Condition = {
                          + StringLike = {
                              + "s3:prefix" = [
                                  + "processed_reports/*",
                                ]
                            }
                        }
                      + Effect    = "Allow"
                      + Resource  = [
                          + "arn:aws:s3:::example-org-service-alpha-reports-mx",
                        ]
                      + Sid       = "Stmt0"
                    },
                  + {
                      + Action   = [
                          + "s3:GetObject",
                        ]
                      + Effect   = "Allow"
                      + Resource = [
                          + "arn:aws:s3:::example-org-service-alpha-reports-mx/processed_reports/*",
                        ]
                      + Sid      = "Stmt1"
                    },
                  + {
                      + Action   = [
                          + "s3:GetObject",
                        ]
                      + Effect   = "Allow"
                      + Resource = [
                          + "arn:aws:s3:::example-org-service-alpha-reports-mx/exports/*/summary.json",
                        ]
                      + Sid      = "JustifiedWildcard2"
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + role        = "service-gamma-mx-workload"
    }

Plan: 3 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + aws_region    = "us-east-1"
  + country       = "mx"
  + workload_role = "service-gamma-mx-workload"
```
</details>

For testing purposes, if you remove the `justification` from the third statement in `iam.auto.tfvars` and plan again, the `iam-role` module refuses it:
```
Error: Invalid value for variable

  on iam.tf line 29, in module "iam":
  29:   policy_statements               = var.iam_policy_statements
    ├────────────────
    │ var.policy_statements is list of object with 1 element

Least privilege: wildcard actions/resources need a `justification` of at
least 20 characters.

This was checked by the validation rule at
../../../modules/iam-role/main.tf:47,3-13.
```

# Next Steps
When the solution gets to Production, we will separate this monorepo into multiple repositories, for example a repository for terraform modules (or a repository per TF module), so we can have "imports" in the services repositories like:
```
module "s3" {
  source = "git::https://github.com/some-example-org/infra-modules.git//modules/s3?ref=s3/v1"
```
And we can have semantic versioning like `s3/v1`, `s3/v1.0` and `s3/v1.0.0`, so the users can pin to an specific version of the modules.
