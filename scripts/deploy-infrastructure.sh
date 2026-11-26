#!/usr/bin/env bash
# Usage: ./scripts/deploy-infrastructure.sh [--skip-controller]
set -euo pipefail

REGION="${AWS_REGION:-eu-west-1}"
CLUSTER="starttech-cluster"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
SKIP_CONTROLLER=false
[[ "${1:-}" == "--skip-controller" ]] && SKIP_CONTROLLER=true

echo "==> Terraform fmt / init / validate"
terraform -chdir="$TF_DIR" fmt -recursive
terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" validate

echo "==> Terraform plan"
terraform -chdir="$TF_DIR" plan -input=false

echo "==> Terraform apply"
terraform -chdir="$TF_DIR" apply -auto-approve -input=false

if [[ "$SKIP_CONTROLLER" == "true" ]]; then
  echo "Skipping AWS Load Balancer Controller install."
  exit 0
fi

echo "==> Updating kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"

VPC_ID=$(terraform -chdir="$TF_DIR" output -raw vpc_id)
ROLE_ARN=$(terraform -chdir="$TF_DIR" output -raw lb_controller_role_arn)

echo "==> Installing AWS Load Balancer Controller (idempotent)"
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ROLE_ARN"

kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
echo "==> Done"