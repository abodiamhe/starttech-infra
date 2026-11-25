variable "bucket_id" {
  type = string
}
variable "bucket_arn" {
  type = string
}
variable "bucket_regional_domain_name" {
  type = string
}

# DNS name of the ALB created by the Ingress. Empty on the first apply.
variable "alb_dns_name" {
  type    = string
  default = ""
}