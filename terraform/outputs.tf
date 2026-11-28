output "cluster_name" {
  value = module.eks.cluster_name
}
output "nat_public_ip" {
  value = module.networking.nat_public_ip
}
output "lb_controller_role_arn" {
  value = module.eks.lb_controller_role_arn
}
output "vpc_id" {
  value = module.networking.vpc_id
}
output "frontend_bucket_name" {
  value = module.storage.bucket_id
}
output "ecr_repository_url" {
  value = module.storage.ecr_repository_url
}
output "redis_endpoint" {
  value = module.database.redis_endpoint
}
output "cloudfront_distribution_id" {
  value = module.cdn.distribution_id
}
output "cloudfront_domain_name" {
  value = module.cdn.domain_name
}

# --------------------------------
output "grader_user_name" {
  value = aws_iam_user.grader.name
}
output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "github_infra_role_arn" {
  value = aws_iam_role.github_infra.arn
}

output "github_app_role_arn" {
  value = aws_iam_role.github_app.arn
}