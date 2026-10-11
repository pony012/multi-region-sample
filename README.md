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
We will test the first IAM module that is prepared to be associated with eks pod identity:
```
source scripts/localstack.env
cd services/service-alpha/.tf
terraform init -input=false -backend-config=../../../backend.hcl
terraform apply -input=false -auto-approve -var eks_pod_identity=false # eks_pod_identity=false because localstack doesn't support eks
aws iam get-role --role-name service-alpha-mx-workload --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal' --output text --no-cli-pager
aws s3 ls s3://tfstate-000000000000-us-east-1 --recursive # We should see the current tf state

terraform plan -input=false -var eks_pod_identity=false \
  -var 'iam_policy_statements=[{actions=["s3:*"],resources=["*"]}]' 2>&1 | grep -m1 "Least privilege" # Validate that we cannot create non-justified wildcard statements
```

## Step 2
We could test that we're going to generate different roles for different countries, with different conventional names:
```
cd services/service-alpha/.tf/
terraform init -input=false -backend-config=../../../backend.hcl
terraform plan -var region=mx -var eks_pod_identity=false
terraform plan -var region=br -var eks_pod_identity=false
```
We'll see that for mx we're getting:
```
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
```
And for br we're getting
```
module.iam.aws_iam_role.this: Refreshing state... [id=service-alpha-mx-workload]
module.iam.aws_iam_role_policy.custom[0]: Refreshing state... [id=service-alpha-mx-workload:custom]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
-/+ destroy and then create replacement

Terraform will perform the following actions:

  # module.iam.aws_iam_role.this must be replaced
-/+ resource "aws_iam_role" "this" {
      ~ arn                   = "arn:aws:iam::000000000000:role/service-alpha-mx-workload" -> (known after apply)
      ~ create_date           = "2026-10-11T07:39:29Z" -> (known after apply)
      ~ id                    = "service-alpha-mx-workload" -> (known after apply)
      ~ managed_policy_arns   = [] -> (known after apply)
      ~ name                  = "service-alpha-mx-workload" -> "service-alpha-br-workload" # forces replacement
      + name_prefix           = (known after apply)
      - tags                  = {} -> null
      ~ tags_all              = {
          + "Country"    = "br"
          + "Owner"      = "Guild-Ledger"
          + "Repository" = "github.com/some-example-org/service-alpha"
            # (4 unchanged elements hidden)
        }
      ~ unique_id             = "AROAQAAAAAAAAN6AAEGPD" -> (known after apply)
        # (6 unchanged attributes hidden)

      ~ inline_policy (known after apply)
      - inline_policy {
          - name   = "custom" -> null
          - policy = jsonencode(
                {
                  - Statement = [
                      - {
                          - Action   = [
                              - "cloudwatch:PutMetricData",
                            ]
                          - Effect   = "Allow"
                          - Resource = [
                              - "*",
                            ]
                          - Sid      = "JustifiedWildcard0"
                        },
                    ]
                  - Version   = "2012-10-17"
                }
            ) -> null
        }
    }

  # module.iam.aws_iam_role_policy.custom[0] must be replaced
-/+ resource "aws_iam_role_policy" "custom" {
      ~ id          = "service-alpha-mx-workload:custom" -> (known after apply)
        name        = "custom"
      + name_prefix = (known after apply)
      ~ role        = "service-alpha-mx-workload" -> "service-alpha-br-workload" # forces replacement
        # (1 unchanged attribute hidden)
    }

Plan: 2 to add, 0 to change, 2 to destroy.

Changes to Outputs:
  + aws_region    = "sa-east-1"
  + country       = "br"
  ~ workload_role = "service-alpha-mx-workload" -> "service-alpha-br-workload"
```