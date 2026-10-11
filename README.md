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

We're working with workspaces, so we can ensure that a workspace for a given country cannot be aplied to another country by mistake:
<details>
<summary>Correct workspace validation</summary>

```
.tf git:(feat/multi-state-multi-service) ✗ terraform apply -input=false -var-file=mx.tfvars -var eks_pod_identity=false
module.iam.aws_iam_role.this: Refreshing state... [id=service-alpha-mx-workload]
module.iam.aws_iam_role_policy.custom[0]: Refreshing state... [id=service-alpha-mx-workload:custom]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  ~ update in-place

Terraform will perform the following actions:

  # module.iam.aws_iam_role.this will be updated in-place
  ~ resource "aws_iam_role" "this" {
        id                    = "service-alpha-mx-workload"
        name                  = "service-alpha-mx-workload"
        tags                  = {}
      ~ tags_all              = {
          + "Compliance" = "ARCO"
          + "Country"    = "mx"
          + "Owner"      = "Guild-Ledger"
          + "Repository" = "github.com/some-example-org/service-alpha"
            # (4 unchanged elements hidden)
        }
        # (11 unchanged attributes hidden)

        # (1 unchanged block hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.

Changes to Outputs:
  + aws_region    = "us-east-1"
  + country       = "mx"

Do you want to perform these actions in workspace "mx"?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

module.iam.aws_iam_role.this: Modifying... [id=service-alpha-mx-workload]
module.iam.aws_iam_role.this: Modifications complete after 0s [id=service-alpha-mx-workload]

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.

Outputs:

aws_region = "us-east-1"
country = "mx"
workload_role = "service-alpha-mx-workload"
```

**This should fail because os missconfiguration of region**

```
➜  .tf git:(feat/multi-state-multi-service) ✗ terraform plan -input=false -var-file=co.tfvars

Changes to Outputs:
  ~ country = "mx" -> "co"

You can apply this plan to save these new output values to the Terraform state, without changing any real infrastructure.
╷
│ Error: Module output value precondition failed
│
│   on ../../../modules/context/main.tf line 101, in output "aws_region":
│  101:     condition     = var.workspace == var.region
│     ├────────────────
│     │ var.region is "co"
│     │ var.workspace is "mx"
│
│ Workspace "mx" does not match country "co". Run: terraform workspace select -or-create co  (or TF_WORKSPACE=co).
╵
```

**and then when we change workspace:**

```
➜  .tf git:(feat/multi-state-multi-service) ✗ terraform workspace select -or-create co
Created and switched to workspace "co"!

You're now on a new, empty workspace. Workspaces isolate their state,
so if you run "terraform plan" Terraform will not see any existing state
for this configuration.
➜  .tf git:(feat/multi-state-multi-service) ✗ terraform apply -input=false -var-file=co.tfvars -var eks_pod_identity=false
...
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

aws_region = "us-east-2"
country = "co"
workload_role = "service-alpha-co-workload"
```
</details>

After that validation, we can safetly create the infra for all countries with the script `validate_deployments.sh`

<details>
<summary>Deployment for all three regions</summary>

```
➜  multi-region-sample git:(feat/multi-state-multi-service) ✗ ./validate_deployments.sh
Switched to workspace "mx".
module.iam.aws_iam_role.this: Refreshing state... [id=service-alpha-mx-workload]
module.iam.aws_iam_role_policy.custom[0]: Refreshing state... [id=service-alpha-mx-workload:custom]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration and found no differences, so no changes are needed.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

aws_region = "us-east-1"
country = "mx"
workload_role = "service-alpha-mx-workload"
Switched to workspace "co".
module.iam.aws_iam_role.this: Refreshing state... [id=service-alpha-co-workload]
module.iam.aws_iam_role_policy.custom[0]: Refreshing state... [id=service-alpha-co-workload:custom]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration and found no differences, so no changes are needed.

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

aws_region = "us-east-2"
country = "co"
workload_role = "service-alpha-co-workload"
Created and switched to workspace "br"!

You're now on a new, empty workspace. Workspaces isolate their state,
so if you run "terraform plan" Terraform will not see any existing state
for this configuration.

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.iam.aws_iam_role.this will be created
  + resource "aws_iam_role" "this" {
      + arn                   = (known after apply)
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
      + create_date           = (known after apply)
      + force_detach_policies = false
      + id                    = (known after apply)
      + managed_policy_arns   = (known after apply)
      + max_session_duration  = 3600
      + name                  = "service-alpha-br-workload"
      + name_prefix           = (known after apply)
      + path                  = "/"
      + tags_all              = {
          + "CostCenter" = "Engineering"
          + "Country"    = "br"
          + "ManagedBy"  = "terraform"
          + "Owner"      = "Guild-Ledger"
          + "Repository" = "github.com/some-example-org/service-alpha"
          + "Service"    = "service-alpha"
          + "Team"       = "example-team"
        }
      + unique_id             = (known after apply)

      + inline_policy (known after apply)
    }

  # module.iam.aws_iam_role_policy.custom[0] will be created
  + resource "aws_iam_role_policy" "custom" {
      + id          = (known after apply)
      + name        = "custom"
      + name_prefix = (known after apply)
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
      + role        = "service-alpha-br-workload"
    }

Plan: 2 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + aws_region    = "sa-east-1"
  + country       = "br"
  + workload_role = "service-alpha-br-workload"
module.iam.aws_iam_role.this: Creating...
module.iam.aws_iam_role.this: Creation complete after 0s [id=service-alpha-br-workload]
module.iam.aws_iam_role_policy.custom[0]: Creating...
module.iam.aws_iam_role_policy.custom[0]: Creation complete after 0s [id=service-alpha-br-workload:custom]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

aws_region = "sa-east-1"
country = "br"
workload_role = "service-alpha-br-workload"

Created and switched to workspace "mx"!

You're now on a new, empty workspace. Workspaces isolate their state,
so if you run "terraform plan" Terraform will not see any existing state
for this configuration.


Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.iam.aws_iam_role.this will be created
  + resource "aws_iam_role" "this" {
      + arn                   = (known after apply)
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
      + create_date           = (known after apply)
      + force_detach_policies = false
      + id                    = (known after apply)
      + managed_policy_arns   = (known after apply)
      + max_session_duration  = 3600
      + name                  = "service-beta-mx-workload"
      + name_prefix           = (known after apply)
      + path                  = "/"
      + tags_all              = {
          + "CostCenter" = "R+D"
          + "Country"    = "mx"
          + "ManagedBy"  = "terraform"
          + "Owner"      = "Chapter-Data"
          + "Repository" = "github.com/some-example-org/service-beta"
          + "Service"    = "service-beta"
          + "Team"       = "Analytics"
        }
      + unique_id             = (known after apply)

      + inline_policy (known after apply)
    }

  # module.s3["reports"].aws_iam_role_policy.grant[0] will be created
  + resource "aws_iam_role_policy" "grant" {
      + id          = (known after apply)
      + name        = "s3-example-org-service-beta-reports-mx"
      + name_prefix = (known after apply)
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
      + acceleration_status         = (known after apply)
      + acl                         = (known after apply)
      + arn                         = (known after apply)
      + bucket                      = "example-org-service-beta-reports-mx"
      + bucket_domain_name          = (known after apply)
      + bucket_namespace            = (known after apply)
      + bucket_prefix               = (known after apply)
      + bucket_region               = (known after apply)
      + bucket_regional_domain_name = (known after apply)
      + force_destroy               = false
      + hosted_zone_id              = (known after apply)
      + id                          = (known after apply)
      + object_lock_enabled         = (known after apply)
      + policy                      = (known after apply)
      + region                      = "us-east-1"
      + request_payer               = (known after apply)
      + tags_all                    = {
          + "CostCenter" = "R+D"
          + "Country"    = "mx"
          + "ManagedBy"  = "terraform"
          + "Owner"      = "Chapter-Data"
          + "Repository" = "github.com/some-example-org/service-beta"
          + "Service"    = "service-beta"
          + "Team"       = "Analytics"
        }
      + website_domain              = (known after apply)
      + website_endpoint            = (known after apply)

      + cors_rule (known after apply)

      + grant (known after apply)

      + lifecycle_rule (known after apply)

      + logging (known after apply)

      + object_lock_configuration (known after apply)

      + replication_configuration (known after apply)

      + server_side_encryption_configuration (known after apply)

      + versioning (known after apply)

      + website (known after apply)
    }

  # module.s3["reports"].aws_s3_bucket_public_access_block.this will be created
  + resource "aws_s3_bucket_public_access_block" "this" {
      + block_public_acls       = true
      + block_public_policy     = true
      + bucket                  = (known after apply)
      + id                      = (known after apply)
      + ignore_public_acls      = true
      + region                  = "us-east-1"
      + restrict_public_buckets = true
    }

  # module.s3["reports"].aws_s3_bucket_server_side_encryption_configuration.this will be created
  + resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
      + bucket = (known after apply)
      + id     = (known after apply)
      + region = "us-east-1"

      + rule {
          + blocked_encryption_types = (known after apply)
          + bucket_key_enabled       = (known after apply)

          + apply_server_side_encryption_by_default {
              + kms_master_key_id = (known after apply)
              + sse_algorithm     = "AES256"
            }
        }
    }

  # module.s3["reports"].aws_s3_bucket_versioning.this will be created
  + resource "aws_s3_bucket_versioning" "this" {
      + bucket = (known after apply)
      + id     = (known after apply)
      + region = "us-east-1"

      + versioning_configuration {
          + mfa_delete = (known after apply)
          + status     = "Enabled"
        }
    }

Plan: 6 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + aws_region    = "us-east-1"
  + buckets       = [
      + (known after apply),
    ]
  + country       = "mx"
  + workload_role = "service-beta-mx-workload"
module.iam.aws_iam_role.this: Creating...
module.s3["reports"].aws_s3_bucket.this: Creating...
module.iam.aws_iam_role.this: Creation complete after 0s [id=service-beta-mx-workload]
module.s3["reports"].aws_iam_role_policy.grant[0]: Creating...
module.s3["reports"].aws_iam_role_policy.grant[0]: Creation complete after 0s [id=service-beta-mx-workload:s3-example-org-service-beta-reports-mx]
module.s3["reports"].aws_s3_bucket.this: Creation complete after 0s [id=example-org-service-beta-reports-mx]
module.s3["reports"].aws_s3_bucket_public_access_block.this: Creating...
module.s3["reports"].aws_s3_bucket_versioning.this: Creating...
module.s3["reports"].aws_s3_bucket_server_side_encryption_configuration.this: Creating...
module.s3["reports"].aws_s3_bucket_public_access_block.this: Creation complete after 0s [id=example-org-service-beta-reports-mx]
module.s3["reports"].aws_s3_bucket_server_side_encryption_configuration.this: Creation complete after 0s [id=example-org-service-beta-reports-mx]
module.s3["reports"].aws_s3_bucket_versioning.this: Creation complete after 1s [id=example-org-service-beta-reports-mx]

Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

aws_region = "us-east-1"
buckets = [
  "example-org-service-beta-reports-mx",
]
country = "mx"
workload_role = "service-beta-mx-workload"
Created and switched to workspace "co"!

You're now on a new, empty workspace. Workspaces isolate their state,
so if you run "terraform plan" Terraform will not see any existing state
for this configuration.

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.iam.aws_iam_role.this will be created
  + resource "aws_iam_role" "this" {
      + arn                   = (known after apply)
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
      + create_date           = (known after apply)
      + force_detach_policies = false
      + id                    = (known after apply)
      + managed_policy_arns   = (known after apply)
      + max_session_duration  = 3600
      + name                  = "service-beta-co-workload"
      + name_prefix           = (known after apply)
      + path                  = "/"
      + tags_all              = {
          + "CostCenter" = "R+D"
          + "Country"    = "co"
          + "ManagedBy"  = "terraform"
          + "Owner"      = "Chapter-Data"
          + "Repository" = "github.com/some-example-org/service-beta"
          + "Service"    = "service-beta"
          + "Team"       = "Analytics"
        }
      + unique_id             = (known after apply)

      + inline_policy (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + aws_region    = "us-east-2"
  + buckets       = []
  + country       = "co"
  + workload_role = "service-beta-co-workload"
module.iam.aws_iam_role.this: Creating...
module.iam.aws_iam_role.this: Creation complete after 0s [id=service-beta-co-workload]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

aws_region = "us-east-2"
buckets = []
country = "co"
workload_role = "service-beta-co-workload"
Created and switched to workspace "br"!

You're now on a new, empty workspace. Workspaces isolate their state,
so if you run "terraform plan" Terraform will not see any existing state
for this configuration.

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.s3["reports"].aws_iam_role_policy.grant[0] will be created
  + resource "aws_iam_role_policy" "grant" {
      + id          = (known after apply)
      + name        = "s3-example-org-service-beta-reports-br"
      + name_prefix = (known after apply)
      + policy      = jsonencode(
            {
              + Statement = [
                  + {
                      + Action   = [
                          + "s3:ListBucket",
                        ]
                      + Effect   = "Allow"
                      + Resource = [
                          + "arn:aws:s3:::example-org-service-beta-reports-br",
                        ]
                      + Sid      = "Bucket"
                    },
                  + {
                      + Action   = [
                          + "s3:GetObject",
                        ]
                      + Effect   = "Allow"
                      + Resource = [
                          + "arn:aws:s3:::example-org-service-beta-reports-br/*",
                        ]
                      + Sid      = "Objects"
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + role        = "service-beta-br-workload"
    }

  # module.s3["reports"].aws_s3_bucket.this will be created
  + resource "aws_s3_bucket" "this" {
      + acceleration_status         = (known after apply)
      + acl                         = (known after apply)
      + arn                         = (known after apply)
      + bucket                      = "example-org-service-beta-reports-br"
      + bucket_domain_name          = (known after apply)
      + bucket_namespace            = (known after apply)
      + bucket_prefix               = (known after apply)
      + bucket_region               = (known after apply)
      + bucket_regional_domain_name = (known after apply)
      + force_destroy               = false
      + hosted_zone_id              = (known after apply)
      + id                          = (known after apply)
      + object_lock_enabled         = (known after apply)
      + policy                      = (known after apply)
      + region                      = "sa-east-1"
      + request_payer               = (known after apply)
      + tags_all                    = {
          + "CostCenter" = "R+D"
          + "Country"    = "br"
          + "ManagedBy"  = "terraform"
          + "Owner"      = "Chapter-Data"
          + "Repository" = "github.com/some-example-org/service-beta"
          + "Service"    = "service-beta"
          + "Team"       = "Analytics"
        }
      + website_domain              = (known after apply)
      + website_endpoint            = (known after apply)

      + cors_rule (known after apply)

      + grant (known after apply)

      + lifecycle_rule (known after apply)

      + logging (known after apply)

      + object_lock_configuration (known after apply)

      + replication_configuration (known after apply)

      + server_side_encryption_configuration (known after apply)

      + versioning (known after apply)

      + website (known after apply)
    }

  # module.s3["reports"].aws_s3_bucket_public_access_block.this will be created
  + resource "aws_s3_bucket_public_access_block" "this" {
      + block_public_acls       = true
      + block_public_policy     = true
      + bucket                  = (known after apply)
      + id                      = (known after apply)
      + ignore_public_acls      = true
      + region                  = "sa-east-1"
      + restrict_public_buckets = true
    }

  # module.s3["reports"].aws_s3_bucket_server_side_encryption_configuration.this will be created
  + resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
      + bucket = (known after apply)
      + id     = (known after apply)
      + region = "sa-east-1"

      + rule {
          + blocked_encryption_types = (known after apply)
          + bucket_key_enabled       = (known after apply)

          + apply_server_side_encryption_by_default {
              + kms_master_key_id = (known after apply)
              + sse_algorithm     = "AES256"
            }
        }
    }

  # module.s3["reports"].aws_s3_bucket_versioning.this will be created
  + resource "aws_s3_bucket_versioning" "this" {
      + bucket = (known after apply)
      + id     = (known after apply)
      + region = "sa-east-1"

      + versioning_configuration {
          + mfa_delete = (known after apply)
          + status     = "Enabled"
        }
    }

  # module.iam.aws_iam_role.this will be created
  + resource "aws_iam_role" "this" {
      + arn                   = (known after apply)
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
      + create_date           = (known after apply)
      + force_detach_policies = false
      + id                    = (known after apply)
      + managed_policy_arns   = (known after apply)
      + max_session_duration  = 3600
      + name                  = "service-beta-br-workload"
      + name_prefix           = (known after apply)
      + path                  = "/"
      + tags_all              = {
          + "CostCenter" = "R+D"
          + "Country"    = "br"
          + "ManagedBy"  = "terraform"
          + "Owner"      = "Chapter-Data"
          + "Repository" = "github.com/some-example-org/service-beta"
          + "Service"    = "service-beta"
          + "Team"       = "Analytics"
        }
      + unique_id             = (known after apply)

      + inline_policy (known after apply)
    }

Plan: 6 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + aws_region    = "sa-east-1"
  + buckets       = []
  + country       = "br"
  + workload_role = "service-beta-br-workload"
module.iam.aws_iam_role.this: Creating...
module.iam.aws_iam_role.this: Creation complete after 0s [id=service-beta-br-workload]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

aws_region = "sa-east-1"
buckets = []
country = "br"
workload_role = "service-beta-br-workload"
```
</details>

After this run, we can check the roles and s3 buckets created:

```
$ aws iam list-roles --query 'Roles[].RoleName' --output table --no-cli-pager
-------------------------------
|          ListRoles          |
+-----------------------------+
|  service-alpha-mx-workload  |
|  service-alpha-br-workload  |
|  service-beta-mx-workload   |
|  service-beta-co-workload   |
|  service-beta-br-workload   |
|  service-alpha-co-workload  |
+-----------------------------+
$ aws s3 ls
2026-10-11 12:29:54 example-org-service-beta-reports-br
2026-10-11 12:12:12 example-org-service-beta-reports-mx
2026-10-10 20:04:01 tfstate-000000000000-us-east-1
```

# Next Steps
When the solution gets to Production, we will separate this monorepo into multiple repositories, for example a repository for terraform modules (or a repository per TF module), so we can have "imports" in the services repositories like:
```
module "s3" {
  source = "git::https://github.com/some-example-org/infra-modules.git//modules/s3?ref=s3/v1"
```
And we can have semantic versioning like `s3/v1`, `s3/v1.0` and `s3/v1.0.0`, so the users can pin to an specific version of the modules.
