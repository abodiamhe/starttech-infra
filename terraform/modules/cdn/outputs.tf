
output "distribution_id" {
  value = aws_cloudfront_distribution.starttech_cdn.id
}
output "distribution_arn" {
  value = aws_cloudfront_distribution.starttech_cdn.arn
}
output "domain_name" {
  value = aws_cloudfront_distribution.starttech_cdn.domain_name
}