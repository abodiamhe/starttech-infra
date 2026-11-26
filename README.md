Prerequisite: an S3 bucket for Terraform state must exist before the first terraform init. See scripts/deploy-infrastructure.sh for the bootstrap commands.

The workflow:

1: Now: apply with a placeholder ALB address. The S3/frontend half works fully.
2: Step 8: deploy the app, copy the real ALB DNS name, set alb_dns_name, and re-apply. This makes the /api/* path work.