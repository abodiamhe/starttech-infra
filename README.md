# starttech-infra

Infrastructure as Code for the StartTech platform: a React frontend and a Go API running on AWS, provisioned with Terraform and deployed through GitHub Actions.

The application code, Kubernetes manifests and app pipelines live in the companion repo: **starttech-application** (`<link-to-application-repo>`).

## Architecture

```
User ──HTTPS──► CloudFront (single distribution)
                  ├─ /*      ──► S3 (private, via OAC)         Origin ID: S3-Frontend
                  └─ /api/*  ──► ALB (HTTP, created by Ingress) Origin ID: ALB-Backend
                                     │
                                     ▼
                           EKS pods (port 8080, private subnets)
                              ├─► ElastiCache Redis (private subnets)
                              └─► MongoDB Atlas (external, via NAT gateway)
```

**Why one CloudFront distribution?** The browser only ever talks to one HTTPS domain. The frontend calls the API with relative paths (`/api/v1/...`), and CloudFront forwards `/api/*` to the ALB over HTTP. This removes the mixed-content problem without needing a custom domain or ACM certificate.

**SPA routing.** CloudFront rewrites `403` and `404` responses to `/index.html` with status `200`, so refreshing a client-side route like `/dashboard` loads the React app instead of an S3 error.

## Repository layout

```
starttech-infra/
├── .github/workflows/infrastructure-deploy.yml   # fmt, validate, apply
├── terraform/
│   ├── main.tf                    # providers, backend, module wiring, grader user, GitHub OIDC
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── networking/            # VPC, subnets, IGW, NAT, route tables
│       ├── eks/                   # cluster, node group, IAM roles, OIDC/IRSA, LB controller role
│       ├── storage/               # private S3 bucket, ECR repository
│       ├── cdn/                   # CloudFront, OAC, bucket policy
│       └── database/              # ElastiCache Redis
├── scripts/deploy-infrastructure.sh
└── README.md
```

## Resources and naming

| Resource | Identifier |
|---|---|
| VPC | `starttech-vpc` (10.0.0.0/16) |
| EKS cluster | `starttech-cluster` (Kubernetes 1.34) |
| Managed node group | `starttech-node-group` (2 x `t3.medium`, private subnets) |
| S3 frontend bucket | `starttech-frontend-bucket-<account-id>` |
| ECR repository | `starttech-backend-api` (scan on push) |
| ElastiCache Redis | `starttech-redis` (`cache.t3.micro`, single node) |
| CloudFront origins | `S3-Frontend`, `ALB-Backend` |
| Container port | `8080` |
| Grader IAM user | `start-tech-grader` (read-only) |

## Module summary

- **networking**: 2 public subnets (tagged `kubernetes.io/role/elb = 1`) and 2 private subnets (tagged `kubernetes.io/role/internal-elb = 1`) across two AZs. One NAT gateway handles egress for the private subnets.
- **eks**: Control plane and node IAM roles use the standard managed policies (`AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEKS_CNI_Policy`). An OIDC provider enables IAM Roles for Service Accounts (IRSA), and a dedicated role is created for the AWS Load Balancer Controller. Cluster access uses EKS access entries.
- **storage**: Private S3 bucket with all four public access block settings enabled, encryption and versioning. ECR repository with scan on push and a lifecycle policy that keeps the last 10 images.
- **cdn**: One distribution with Origin Access Control for S3. The default behavior (`*`) serves S3 and redirects HTTP to HTTPS. The ordered behavior `/api/*` goes to the ALB with `min_ttl = default_ttl = max_ttl = 0` and forwards all headers, cookies and query strings. The bucket policy allows reads only from this distribution (`AWS:SourceArn`).
- **database**: Single-node Redis in private subnets. Its security group allows port 6379 only from the EKS cluster security group.

## Prerequisites

AWS CLI v2, Terraform 1.10 or newer, kubectl, Helm, and an AWS identity with admin rights for the first apply.

## First-time setup

### 1. Create the remote state bucket (one time, manual)

```bash
aws s3api create-bucket --bucket <state-bucket> --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1
aws s3api put-bucket-versioning --bucket <state-bucket> \
  --versioning-configuration Status=Enabled
```

Set the bucket name in the `backend "s3"` block in `terraform/main.tf`. State locking uses the S3 native lockfile (`use_lockfile = true`).

### 2. Configure variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit github_owner, region, etc.
```

`terraform.tfvars` is gitignored.

### 3. Apply

```bash
./scripts/deploy-infrastructure.sh
```

This runs `terraform fmt`, `init`, `validate`, `plan` and `apply`, then installs the AWS Load Balancer Controller with Helm. Use `--skip-controller` to run Terraform only.

### 4. Wire the ALB into CloudFront (one-time, two-step)

The ALB is created by the Kubernetes Ingress in the application repo, which happens after Terraform runs, but CloudFront needs the ALB hostname. So:

1. First apply: `alb_dns_name` is empty and CloudFront uses a placeholder origin. `/api/*` returns 502 or 504 at this point, which is expected.
2. Deploy the backend from the application repo. The Ingress creates the ALB.
3. Read the hostname:
   ```bash
   kubectl get ingress backend-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```
4. Set it in **both** places, then re-apply:
   - GitHub repo variable `ALB_DNS_NAME` (used by the pipeline)
   - `alb_dns_name` in your local `terraform.tfvars`

> The pipeline passes `ALB_DNS_NAME` as `TF_VAR_alb_dns_name`. If it is only set locally, the next pipeline run resets the CloudFront origin to the placeholder and breaks `/api/*`.

## CI/CD: `infrastructure-deploy.yml`

Triggers on pushes to `main` that change `terraform/**`, and manually via `workflow_dispatch`.

Steps: checkout, set up Terraform, assume the AWS role via GitHub OIDC, `terraform fmt -check -recursive`, `init`, `validate`, `plan`, then `apply -auto-approve`.

- **Authentication:** GitHub OIDC. There are no long-lived AWS keys in GitHub. The role `starttech-github-infra-role` can only be assumed by the `main` branch of this repo.
- **GitHub repo variables:** `AWS_ROLE_ARN` (the role ARN from `terraform output github_infra_role_arn`) and `ALB_DNS_NAME`.
- **Concurrency:** a `concurrency` group prevents two applies from running at once, and the S3 lockfile protects the state.

## Grader access

The IAM user `start-tech-grader` has an inline policy with exactly the read-only actions required by the assessment: S3 (`ListAllMyBuckets`, `GetBucketPublicAccessBlock`, `ListBucket`), CloudFront (`ListDistributions`, `GetDistributionConfig`), EKS (`DescribeCluster`, `ListNodegroups`, `DescribeNodegroup`) and ElastiCache (`DescribeCacheClusters`). Access keys and the console password are created with the CLI so they never enter Terraform state, and are shared only through the submission document.

## Verification

```bash
cd terraform
DIST=$(terraform output -raw cloudfront_distribution_id)
DOMAIN=$(terraform output -raw cloudfront_domain_name)

# Origins and behaviours
aws cloudfront get-distribution-config --id $DIST --query 'DistributionConfig.Origins.Items[].Id'
aws cloudfront get-distribution-config --id $DIST \
  --query 'DistributionConfig.CacheBehaviors.Items[0].{path:PathPattern,min:MinTTL,def:DefaultTTL,max:MaxTTL}'

# SPA fallback: should print 200
curl -s -o /dev/null -w "%{http_code}\n" https://$DOMAIN/dashboard

# API through CloudFront (after the backend is deployed)
curl -s https://$DOMAIN/api/v1/health
```

## Design decisions and trade-offs

- **Custom error responses are distribution-wide.** The SPA fix (403/404 to `index.html`) also applies to `/api/*`, so an API 404 would be returned as `index.html` with a 200. The assessment requires this configuration, so the API avoids relying on 403/404 for client logic. The usual production alternative is a CloudFront Function on the default behavior only.
- **`forwarded_values` on the API behavior.** It is the legacy form, but it makes the TTLs, headers, cookies and query string forwarding explicit in code. The default behavior uses the managed `CachingOptimized` cache policy.
- **ALB created by the Ingress, not Terraform.** This keeps `ingress.yaml` on the standard `alb` ingress class, at the cost of the one-time hostname hand-off described above.
- **Single NAT gateway.** This lowers cost. For production, use one NAT gateway per AZ.
- **Pipeline role is effectively admin.** Terraform manages IAM, EKS, VPC and CloudFront, so the role needs broad rights. The trust policy (repo and branch pinned) is what limits the risk.
- **`-auto-approve` has no human gate.** It is required by the assessment. In production, add a plan review step or a GitHub Environment with required approvers.
- **Load Balancer Controller installed with Helm, not Terraform.** The Helm provider needs the cluster to exist at configuration time, which causes a chicken-and-egg problem on the first apply.

## Secrets

No secrets are committed to this repo. `terraform.tfvars` is gitignored, AWS access uses OIDC, and the MongoDB connection string is stored as a GitHub Secret and a Kubernetes Secret in the application repo.

## Cost and teardown

EKS, the NAT gateway and the worker nodes are billed hourly. Tear down when finished:

```bash
# 1. Delete the Ingress first so the controller removes the ALB it created
kubectl delete ingress backend-api

# 2. Then destroy everything Terraform manages
cd terraform
terraform destroy
```

If you skip step 1, the ALB and its security groups still sit inside the VPC and the destroy fails on the subnets.
