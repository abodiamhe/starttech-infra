variable "vpc_id" {
  type = string
}
variable "private_subnet_ids" {
  type = list(string)
}

# Security group the EKS worker nodes use
variable "eks_node_security_group_id" {
  type = string
}

variable "node_type" {
  type    = string
  default = "cache.t3.small"
}