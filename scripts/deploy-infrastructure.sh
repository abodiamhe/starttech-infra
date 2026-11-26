#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-eu-west-1}"
LBC_CHART_VERSION="3.6.3"   # pin a version; check the eks-charts releases for the current one

cd "$(dirname "$0")/../terraform"

echo "==> Phase A: Terraform"
terraform init -input=false
terraform fmt -check -recursive
terraform validate
terraform apply -auto-approve -input=false

echo "==> Reading outputs"
CLUSTER=$(terraform output -raw cluster_name)
VPC_ID=$(terraform output -raw vpc_id)
ROLE_ARN=$(terraform output -raw lb_controller_role_arn)

echo "==> Phase B: connect to cluster"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
kubectl wait --for=condition=Ready nodes --all --timeout=600s

echo "==> Install/upgrade AWS Load Balancer Controller"
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version "$LBC_CHART_VERSION" \
  --set clusterName="$CLUSTER" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$ROLE_ARN" \
  --wait --timeout 5m

kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
echo "==> Done"