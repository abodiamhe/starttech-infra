data "aws_caller_identity" "current" {}

# ---------- S3 bucket for the React build ---------- 
# The account ID suffix keeps it globally unique.
resource "aws_s3_bucket" "starttech_frontend_bucket" {
  bucket        = "starttech-frontend-bucket-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # lets terraform destroy remove a non-empty bucket

  tags = {
    Name = "starttech-frontend-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "starttech_frontend_bucket" {
  bucket = aws_s3_bucket.starttech_frontend_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.starttech_frontend_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.starttech_frontend_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ---------- ECR repository for the Go backend ----------
resource "aws_ecr_repository" "starttech_backend_api" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true # lets terraform destroy remove a repo with images

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.starttech_backend_api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}