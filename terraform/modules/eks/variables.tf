variable "cluster_name" {
  type = string
}
variable "kubernetes_version" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "private_subnet_ids" {
  type = list(string)
}
variable "public_subnet_ids" {
  type = list(string)
}

variable "node_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

# Role your GitHub Actions workflow assumes. Leave empty until you create it.
variable "github_actions_role_arn" {
  type    = string
  default = ""
}