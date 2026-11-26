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

data "aws_caller_identity" "current" {}

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

module "cdn" {
  source = "./modules/cdn"

  bucket_id                   = module.storage.bucket_id
  bucket_arn                  = module.storage.bucket_arn
  bucket_regional_domain_name = module.storage.bucket_regional_domain_name
  alb_dns_name                = var.alb_dns_name

  # Ensures the public access block exists before the bucket policy is attached
  depends_on = [module.storage]
}

# ---------- Grader user (read-only, least privilege) ----------
resource "aws_iam_user" "grader" {
  name = "start-tech-grader"
  tags = { Purpose = "assessment-grading" }
}

resource "aws_iam_user_policy" "grader" {
  name = "GraderReadOnly"
  user = aws_iam_user.grader.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GraderReadOnlyS3"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketPublicAccessBlock",
          "s3:ListBucket"
        ]
        Resource = "*"
      },
      {
        Sid    = "GraderReadOnlyCloudFront"
        Effect = "Allow"
        Action = [
          "cloudfront:ListDistributions",
          "cloudfront:GetDistributionConfig"
        ]
        Resource = "*"
      },
      {
        Sid    = "GraderReadOnlyEKS"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListNodegroups",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Sid      = "GraderReadOnlyElastiCache"
        Effect   = "Allow"
        Action   = ["elasticache:DescribeCacheClusters"]
        Resource = "*"
      }
    ]
  })
}

# ---------- GitHub Actions OIDC trust ----------
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ---------- Role assumed by the infrastructure pipeline ----------
resource "aws_iam_role" "github_infra" {
  name = "starttech-github-infra-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # Only the main branch of the infra repo can assume this role
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/starttech-infra:ref:refs/heads/main"
        }
      }
    }]
  })
}

# Terraform creates IAM roles, EKS, VPC, CloudFront and more, so this role is
# effectively admin. The tight trust policy above is what limits the risk.
resource "aws_iam_role_policy_attachment" "github_infra_admin" {
  role       = aws_iam_role.github_infra.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}