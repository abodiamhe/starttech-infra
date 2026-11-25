# Terraform's entry point (tells Terraform where to store its state, configures AWS, and calls a module that builds your networking infrastructure)

terraform {
  required_version = ">= 1.10" # Only run this configuration with Terraform version 1.10 or newer

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # S3 bucket where Terraform will store its state (Note: bucket must already exist)
  backend "s3" {
    bucket = "starttech-tfstate-abodiamhe"
    # (path/name) where the state file will be stored inside the bucket
    key    = "starttech/terraform.tfstate"
    region = "eu-west-1"
    # State locking helps prevent two Terraform operations from modifying the same state simultaneously
    use_lockfile = true
    # This enables server-side encryption for the state object stored in S3
    encrypt = true
  }
}

# configures the AWS provider that Terraform uses to interact with AWS
provider "aws" {
  region = var.aws_region # region to operate in

  # applies default tags to supported resources managed through this provider
  default_tags {
    tags = {
      Project   = "starttech"
      ManagedBy = "terraform"
    }
  }
  # NOTE: use tags to identify all resources belonging to a project or all resources managed by Terraform
}

module "networking" {
  source = "./modules/networking"

  # supply values to the networking module
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# EKS module
module "eks" {
  source = "./modules/eks"

  cluster_name            = var.cluster_name
  kubernetes_version      = var.kubernetes_version
  vpc_id                  = module.networking.vpc_id
  private_subnet_ids      = module.networking.private_subnet_ids
  public_subnet_ids       = module.networking.public_subnet_ids
  github_actions_role_arn = var.github_actions_role_arn
}

module "storage" {
  source = "./modules/storage"
}

module "database" {
  source = "./modules/database"

  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  eks_node_security_group_id = module.eks.cluster_security_group_id
}