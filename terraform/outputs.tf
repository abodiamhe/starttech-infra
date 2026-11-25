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