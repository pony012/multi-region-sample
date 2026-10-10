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
