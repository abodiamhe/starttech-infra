output "cluster_name" {
  value = aws_eks_cluster.starttech_cluster.name
}
output "cluster_endpoint" {
  value = aws_eks_cluster.starttech_cluster.endpoint
}
output "cluster_security_group_id" {
  value = aws_eks_cluster.starttech_cluster.vpc_config[0].cluster_security_group_id
}
output "node_role_arn" {
  value = aws_iam_role.node.arn
}
output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}
output "lb_controller_role_arn" {
  value = aws_iam_role.lb_controller.arn
}