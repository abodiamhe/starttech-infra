# Values from your Terraform outputs
CLUSTER=starttech-cluster
VPC_ID=$(terraform -chdir=terraform output -raw vpc_id)
ROLE_ARN=$(terraform -chdir=terraform output -raw lb_controller_role_arn)
REGION=eu-west-1

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER \
  --set region=$REGION \
  --set vpcId=$VPC_ID \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN

kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
kubectl -n kube-system get deployment aws-load-balancer-controller