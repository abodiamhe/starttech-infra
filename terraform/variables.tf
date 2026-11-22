variable "aws_region" {
  description = "AWS region for infrastructure"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  type    = string
  default = "starttech-cluster"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["eu-west-1a", "eu-west-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}
variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "github_actions_role_arn" {
  type    = string
  default = ""
}