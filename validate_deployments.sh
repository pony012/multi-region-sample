# /bin/bash
source scripts/localstack.test
for s in service-alpha service-beta; do
  for c in mx co br; do
    (cd services/$s/.tf &&
      terraform init -input=false -reconfigure -backend-config=../../../backend.hcl >/dev/null &&
      terraform workspace select -or-create $c &&
      terraform apply -input=false -auto-approve -var-file=$c.tfvars -var eks_pod_identity=false)
  done
done
