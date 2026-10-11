# s3

Private, encrypted (SSE-S3 / AES256) bucket with all public access blocked and versioning on by default. If `grant_role_name` is set, it also attaches a least-privilege inline policy (`s3-<bucket>`) to that role, usually the workload role. Name buckets `<org>-<service>-<purpose>-<country>`.

| `access` | Bucket (`arn:aws:s3:::<name>`) | Objects (`arn:aws:s3:::<name>/*`) |
|---|---|---|
| read | s3:ListBucket | s3:GetObject |
| readwrite (default) | s3:ListBucket | s3:GetObject, s3:PutObject |

```hcl
module "s3" {
  source = "../../../modules/s3"

  name            = "example-org-service-beta-reports-mx"
  access          = "read"
  grant_role_name = module.iam.role_name
}
```