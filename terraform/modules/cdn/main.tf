locals {
  # Placeholder lets the first apply succeed before the ALB exists
  alb_origin_domain = var.alb_dns_name != "" ? var.alb_dns_name : "placeholder.example.com"
}

# ---------- Origin Access Control (S3) ----------
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "starttech-s3-oac"
  description                       = "OAC for the StartTech frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------- Single unified distribution ----------
resource "aws_cloudfront_distribution" "starttech_cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "StartTech unified distribution (S3 frontend + ALB API)"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  # Origin 1: S3 via OAC
  origin {
    domain_name              = var.bucket_regional_domain_name
    origin_id                = "S3-Frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # Origin 2: ALB over HTTP
  origin {
    domain_name = local.alb_origin_domain
    origin_id   = "ALB-Backend"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default behavior (*): React app from S3
  default_cache_behavior {
    target_origin_id       = "S3-Frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS managed policy: Managed-CachingOptimized
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # Ordered behavior (/api/*): Go API on the ALB, no caching
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "ALB-Backend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }
  }

  # SPA routing fix: S3 403/404 -> index.html with 200
  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "starttech-cdn" }
}

# -------- Bucket policy: only this distribution can read the bucket (blocking all public access) --------
data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    sid       = "AllowCloudFrontServicePrincipalReadOnly"
    actions   = ["s3:GetObject"]
    resources = ["${var.bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.starttech_cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = var.bucket_id
  policy = data.aws_iam_policy_document.frontend_bucket.json
}