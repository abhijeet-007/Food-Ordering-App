# infra-as-code-pipeline

Fully functional AWS ECS deployment pipeline for `food-app`.

---

## Architecture Overview

```
Internet
   │
   ▼
[ALB] ── public subnets (2 AZs)
   │
   ▼
[ECS Fargate Service] ── public subnets (2 AZs, with public IPs)
   │
   └─► [CloudWatch Logs]
   │
[ECR Repository]
   │
[S3 Remote State + DynamoDB Lock]
```

**Cost-Optimized Architecture:**
- ✅ No NAT Gateway (saves $64/month)
- ✅ ECS tasks in public subnets with public IPs
- ✅ Security groups restrict access to ALB only
- ✅ Fargate Spot for staging (70% cheaper)

### AWS Resources per Environment (Optimized)

| Resource            | Staging    | Prod       |
|---------------------|------------|------------|
| VPC CIDR            | 10.1.0.0/16| 10.2.0.0/16|
| Subnets             | Public only| Public only|
| ECS Task CPU        | 256        | 512        |
| ECS Task Memory     | 512 MB     | 1024 MB    |
| Min Tasks           | 1          | 1          |
| Max Tasks           | 2          | 3          |
| Log Retention       | 7 days     | 30 days    |
| Fargate Type        | SPOT       | On-Demand  |
| NAT Gateways        | 0          | 0          |

---

## Pipeline Flow

```
PR opened
   │
   ├─► lint (terraform fmt + validate + tflint + hadolint)
   │
   └─► test (docker build + run tests)

Push to main / staging
   │
   ├─► lint → test → build & push to ECR
   │
   ├─► deploy → staging
   │       └─► health check (5 min window)
   │               └─► FAIL → pipeline stops, no prod deploy
   │
   ├─► [MANUAL APPROVAL] ← required for prod
   │
   └─► deploy → production
           └─► health check (5 min window)
                   └─► FAIL → auto rollback to previous task definition
```

---

## Repository Structure

```
infra-as-code-pipeline/
├── .github/
│   └── workflows/
│       └── pipeline.yml          # Full CI/CD pipeline
├── terraform/
│   ├── backend/
│   │   └── bootstrap.sh          # One-time S3 + DynamoDB setup
│   ├── modules/
│   │   ├── networking/           # VPC, subnets, IGW, NAT, route tables
│   │   ├── security/             # Security groups, IAM roles
│   │   ├── compute/              # ECR, ECS, ALB, auto-scaling
│   │   └── monitoring/           # CloudWatch log groups + alarms
│   └── envs/
│       ├── dev/                  # Dev workspace
│       ├── staging/              # Staging workspace
│       └── prod/                 # Production workspace
├── scripts/
│   ├── health-check.sh           # 5-min health check poller
│   └── rollback.sh               # ECS rollback to previous task def
└── docs/
    └── runbook.md                # Failure runbook
```

---

## Quick Start

### 1. Bootstrap remote state (run once)

```bash
cd terraform/backend
chmod +x bootstrap.sh
./bootstrap.sh us-east-1 food-app
```

Update `backend.hcl` in each env with the bucket name printed.

### 2. Configure GitHub Secrets

| Secret               | Description                              |
|----------------------|------------------------------------------|
| `AWS_ROLE_ARN`       | IAM role ARN for staging deployments     |
| `AWS_ROLE_ARN_PROD`  | IAM role ARN for production deployments  |

### 3. Configure GitHub Environments

Create these environments in GitHub → Settings → Environments:
- `staging` — no approval required
- `production-approval` — require 1 reviewer
- `production` — no additional gates

### 4. Deploy manually (first time)

```bash
cd terraform/envs/staging
terraform init -backend-config=backend.hcl
terraform apply -var-file=terraform.tfvars
```

### 5. Push code to trigger pipeline

```bash
git push origin main   # triggers full pipeline with prod approval
git push origin staging # triggers staging deploy only
```

---

## Rollback

Rollback is automatic if the health check fails within 5 minutes of a production deploy.

Manual rollback:

```bash
# Find previous task definition
aws ecs describe-services \
  --cluster food-app-prod-cluster \
  --services food-app-prod-service \
  --query 'services[0].taskDefinition'

# Roll back
bash scripts/rollback.sh \
  food-app-prod-cluster \
  food-app-prod-service \
  arn:aws:ecs:us-east-1:<account>:task-definition/food-app-prod:<PREV_REVISION> \
  us-east-1
```

---

## Estimated Monthly AWS Costs (Ultra-Optimized for 5 Months)

> Ultra-optimized configuration for ap-south-1 region.

| Resource                    | Staging  | Prod      |
|-----------------------------|----------|-----------|
| ECS Fargate (Spot/On-demand)| ~$2      | ~$20      |
| ALB                         | ~$16     | ~$16      |
| NAT Gateway                 | **$0**   | **$0**    |
| ECR storage (10 images)     | ~$1      | ~$1       |
| CloudWatch Logs             | ~$1      | ~$2       |
| **Total (approx)**          | **~$20** | **~$39**  |

**Combined: ~$60/month** (84% reduction from $364, 52% reduction from $124)

**5-Month Total: ~$300** (vs $1,820 original)

### Optimizations Applied:
- Removed dev environment
- **No NAT Gateway** (ECS tasks use public IPs)
- Fargate Spot for staging (70% cheaper)
- Reduced task sizes and counts
- Reduced log retention periods
- ECS tasks in public subnets (secure via security groups)

> See [docs/cost-optimization.md](docs/cost-optimization.md) and [docs/alternative-architectures.md](docs/alternative-architectures.md) for details.

> Use [AWS Pricing Calculator](https://calculator.aws) for precise estimates.

---

## Secrets Management

- All secrets stored in **GitHub Secrets** (AWS credentials) or **AWS Parameter Store**
- Parameter Store path: `/<project>/<env>/<secret-name>`
- ECS task execution role has SSM read access scoped to `/<project>/<env>/*`
- No secrets ever committed to code

---

## Auto-scaling

ECS services scale between `min_capacity` and `max_capacity` based on:
- CPU utilization target: **70%**
- Memory utilization target: **70%**
- Scale-out cooldown: 60s
- Scale-in cooldown: 300s
